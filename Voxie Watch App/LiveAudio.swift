import AVFoundation
import Foundation

/// Half-duplex mono PCM16 audio for the Walkie-Talkie flow.
///
/// - Listening uses the `.playback` category: full speaker volume on Apple
///   Watch. (`.playAndRecord` + `.voiceChat` applied voice processing and
///   played speech very quietly.)
/// - Talking switches to `.playAndRecord` only while the button is held.
/// - Every received buffer is kept until it has really been heard. When the
///   engine is stopped by a route/category change or interruption, unfinished
///   buffers are scheduled again instead of being lost (and wrongly
///   acknowledged as played).
@MainActor
final class LiveAudio {
    private var capture = AVAudioEngine()
    private let playback = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: 16_000, channels: 1, interleaved: false)!
    private let floatFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    private var capturing = false
    private var playbackLevel: Float = 1
    private var observers: [NSObjectProtocol] = []

    private enum Mode { case none, listen, talk }
    private var mode: Mode = .none
    private var sessionActive = false

    private struct Scheduled {
        let id: Int
        let buffer: AVAudioPCMBuffer
        let onPlayed: (@Sendable () -> Void)?
    }
    private var queue: [Scheduled] = []
    private var nextID = 0
    /// Bumped whenever the player is flushed; completions from an older
    /// generation belong to flushed buffers and are ignored.
    private var generation = 0

    /// True while received speech is queued or playing.
    var isPlaying: Bool { !queue.isEmpty }

    init() {
        playback.attach(player)
        playback.connect(player, to: playback.mainMixerNode, format: floatFormat)
        playback.mainMixerNode.outputVolume = playbackLevel

        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: playback, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restartPlayback() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sessionActive = false
                if type == .ended { self.restartPlayback() }
            }
        })
    }

    func setPlaybackVolume(_ value: Float) {
        playbackLevel = min(1, max(0.1, value))
        playback.mainMixerNode.outputVolume = playbackLevel
    }

    private func setMode(_ wanted: Mode) throws {
        let session = AVAudioSession.sharedInstance()
        if mode != wanted {
            switch wanted {
            case .listen:
                do {
                    try session.setCategory(.playback, mode: .default)
                } catch {
                    try session.setCategory(.playAndRecord, mode: .default)
                }
            case .talk:
                #if os(iOS)
                try session.setCategory(.playAndRecord, mode: .default,
                                        options: [.defaultToSpeaker, .allowBluetooth])
                #else
                try session.setCategory(.playAndRecord, mode: .default)
                #endif
            case .none:
                break
            }
            mode = wanted
        }
        if !sessionActive {
            try session.setActive(true)
            sessionActive = true
        }
    }

    /// Ensures the playback engine and player node are running for listening.
    func prepare() throws {
        try setMode(capturing ? .talk : .listen)
        if !playback.isRunning {
            playback.prepare()
            try playback.start()
        }
        if !player.isPlaying { player.play() }
    }

    private func restartPlayback() {
        guard !capturing else { return }
        generation += 1
        player.stop()               // flush; old-generation callbacks are ignored
        guard (try? prepare()) != nil else { return }
        for item in queue { schedule(item) }
    }

    private func schedule(_ item: Scheduled) {
        let scheduledGeneration = generation
        let id = item.id
        player.scheduleBuffer(item.buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finished(id, generation: scheduledGeneration) }
        }
    }

    private func finished(_ id: Int, generation finishedGeneration: Int) {
        // A callback caused by stopping the player (not by real playback)
        // must not count as heard: the buffer is rescheduled on restart.
        guard finishedGeneration == generation, playback.isRunning, player.isPlaying,
              let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let item = queue.remove(at: index)
        item.onPlayed?()
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer, onPlayed: (@Sendable () -> Void)?) {
        nextID += 1
        let item = Scheduled(id: nextID, buffer: buffer, onPlayed: onPlayed)
        queue.append(item)
        schedule(item)
    }

    // MARK: Talking

    func startCapture(onChunk: @escaping @Sendable (Data) -> Void) throws {
        guard !capturing else { return }
        capturing = true
        do {
            try setMode(.talk)
            // A fresh engine picks up the current hardware input format; a
            // reused engine can keep a stale format after a category change
            // and crash on installTap.
            capture = AVAudioEngine()
            let node = capture.inputNode
            let native = node.outputFormat(forBus: 0)
            guard native.sampleRate > 0, native.channelCount > 0 else { throw AudioProblem.noMicrophone }
            guard let converter = AVAudioConverter(from: native, to: pcmFormat) else {
                throw AudioProblem.converter
            }
            let targetFormat = pcmFormat
            let ratio = 16_000 / native.sampleRate
            node.installTap(onBus: 0, bufferSize: 4096, format: native) { buffer, _ in
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 128)
                guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
                var used = false
                var conversionError: NSError?
                converter.convert(to: output, error: &conversionError) { _, status in
                    guard !used else { status.pointee = .noDataNow; return nil }
                    used = true
                    status.pointee = .haveData
                    return buffer
                }
                guard conversionError == nil, output.frameLength > 0,
                      let samples = output.int16ChannelData?[0] else { return }
                onChunk(Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size))
            }
            capture.prepare()
            do {
                try capture.start()
            } catch {
                node.removeTap(onBus: 0)
                throw error
            }
        } catch {
            capturing = false
            restartPlayback()
            throw error
        }
    }

    func stopCapture() {
        guard capturing else { return }
        capture.inputNode.removeTap(onBus: 0)
        capture.stop()
        capturing = false
        // Back to loud listening mode right away, so a reply is audible.
        restartPlayback()
    }

    // MARK: Listening

    /// Short Walkie-Talkie style chirp: rising when a transmission starts,
    /// falling when it ends. Synthesised, so no sound file is needed.
    func playChirp(rising: Bool) {
        guard !capturing, (try? prepare()) != nil else { return }
        let rate = floatFormat.sampleRate
        let length = AVAudioFrameCount(rate * 0.09)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: length),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = length
        let (start, end): (Double, Double) = rising ? (1_250, 1_900) : (1_900, 1_250)
        var phase = 0.0
        for n in 0..<Int(length) {
            let t = Double(n) / Double(length)
            let frequency = start + (end - start) * t
            phase += 2 * Double.pi * frequency / rate
            let envelope = min(1, min(t, 1 - t) * 12)   // fade in/out avoids clicks
            channel[n] = Float(sin(phase) * 0.35 * envelope)
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    func play(_ pcm: Data, onPlayed: @escaping @Sendable () -> Void) throws {
        guard pcm.count >= 2, pcm.count.isMultiple(of: 2) else { onPlayed(); return }
        try prepare()
        let count = pcm.count / 2
        guard let output = AVAudioPCMBuffer(pcmFormat: floatFormat,
                                           frameCapacity: AVAudioFrameCount(count)),
              let channel = output.floatChannelData?[0] else { onPlayed(); return }
        output.frameLength = AVAudioFrameCount(count)
        // Decode little-endian PCM16 without assuming Data has Int16 alignment.
        pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for n in 0..<count {
                let sample = UInt16(raw[n * 2]) | (UInt16(raw[n * 2 + 1]) << 8)
                channel[n] = Float(Int16(bitPattern: sample)) / 32768
            }
        }
        enqueue(output, onPlayed: onPlayed)
    }

    /// Makes a whole recorded message loud and even: gain from the 99.5th
    /// percentile level (so one click or the start chirp can't dominate),
    /// capped at 10×, followed by a soft limiter instead of hard clipping.
    nonisolated static func normalize(_ pcm: Data) -> Data {
        let count = pcm.count / 2
        guard count > 0 else { return pcm }
        var samples = [Int16](repeating: 0, count: count)
        pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for n in 0..<count {
                samples[n] = Int16(bitPattern: UInt16(raw[n * 2]) | (UInt16(raw[n * 2 + 1]) << 8))
            }
        }
        // Histogram of magnitudes (128 bins) to find the 99.5th percentile.
        var histogram = [Int](repeating: 0, count: 128)
        for sample in samples { histogram[min(127, Int(sample.magnitude) >> 8)] += 1 }
        let target = Int(Double(count) * 0.995)
        var cumulative = 0
        var levelBin = 127
        for (bin, value) in histogram.enumerated() {
            cumulative += value
            if cumulative >= target { levelBin = bin; break }
        }
        let level = Double(max(1, levelBin) << 8 + 128)
        guard level > 300 else { return pcm }            // silence: leave as is
        let gain = min(10, 22_000 / level)
        guard gain > 1.05 else { return pcm }
        let drive = 1.6
        let norm = tanh(drive)
        var output = Data(count: count * 2)
        output.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            for n in 0..<count {
                let x = Double(samples[n]) / 32768 * gain
                let limited = tanh(x * drive) / norm         // smooth, never clips
                let value = Int16(max(-32767, min(32767, limited * 32767)))
                let bits = UInt16(bitPattern: value)
                raw[n * 2] = UInt8(bits & 0xff)
                raw[n * 2 + 1] = UInt8(bits >> 8)
            }
        }
        return output
    }
}

private enum AudioProblem: LocalizedError {
    case converter, noMicrophone
    var errorDescription: String? {
        switch self {
        case .converter: return "Audioformaat niet ondersteund"
        case .noMicrophone: return "Geen microfoon beschikbaar"
        }
    }
}
