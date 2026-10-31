import AVFoundation
import Foundation

/// Real-time mono PCM16 frames. The watchOS app must remain running and active.
@MainActor
final class LiveAudio {
    private let capture = AVAudioEngine()
    private let playback = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: 16_000, channels: 1, interleaved: false)!
    private let floatFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    private var capturing = false
    private var sessionConfigured = false
    private var playbackLevel: Float = 1
    private var configurationObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        playback.attach(player)
        playback.connect(player, to: playback.mainMixerNode, format: floatFormat)
        playback.mainMixerNode.outputVolume = playbackLevel

        // Starting/stopping the microphone engine (or a route change) can stop
        // the playback engine. Without restarting it, every later frame was
        // scheduled on a dead engine and stayed silent.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: playback, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restartPlayback() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor [weak self] in
                self?.sessionConfigured = false
                self?.restartPlayback()
            }
        }
    }

    func setPlaybackVolume(_ value: Float) {
        playbackLevel = min(1, max(0.1, value))
        playback.mainMixerNode.outputVolume = playbackLevel
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        if !sessionConfigured {
            #if os(iOS)
            // .playAndRecord bypasses the Ring/Silent switch, including when locked.
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            #else
            // watchOS routes audio to the Watch speaker or connected audio device.
            do {
                try session.setCategory(.playAndRecord, mode: .voiceChat)
            } catch {
                try session.setCategory(.playAndRecord, mode: .default)
            }
            #endif
            sessionConfigured = true
        }
        try session.setActive(true)
    }

    /// Ensures the playback engine and player node are running.
    func prepare() throws {
        try configureSession()
        if !playback.isRunning {
            playback.prepare()
            try playback.start()
        }
        if !player.isPlaying { player.play() }
    }

    private func restartPlayback() {
        guard !capturing else { return }
        try? prepare()
    }

    func startCapture(onChunk: @escaping @Sendable (Data) -> Void) throws {
        guard !capturing else { return }
        try prepare()
        let node = capture.inputNode
        let native = node.outputFormat(forBus: 0)
        // A 0 Hz / 0-channel format means no microphone route is available
        // (simulator without input, permission revoked, audio busy). Installing
        // a tap with it raises an Objective-C exception and crashes the app.
        guard native.sampleRate > 0, native.channelCount > 0 else {
            throw AudioProblem.noMicrophone
        }
        guard let converter = AVAudioConverter(from: native, to: pcmFormat) else {
            throw AudioProblem.converter
        }
        let targetFormat = pcmFormat
        let ratio = 16_000 / native.sampleRate
        // ~170 ms at 48 kHz: avoids flooding HTTPS with tiny sub-50 ms uploads.
        node.installTap(onBus: 0, bufferSize: 8192, format: native) { buffer, _ in
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
        do {
            capture.prepare()
            try capture.start()
            capturing = true
        } catch {
            node.removeTap(onBus: 0)
            throw error
        }
    }

    func stopCapture() {
        guard capturing else { return }
        capture.inputNode.removeTap(onBus: 0)
        capture.stop()
        capturing = false
        // The capture engine shares the audio hardware; bring playback back so
        // the reply from a friend is audible immediately.
        restartPlayback()
    }

    /// Short Walkie-Talkie style chirp: rising when a transmission starts,
    /// falling when it ends. Synthesised, so no sound file is needed.
    func playChirp(rising: Bool) {
        guard (try? prepare()) != nil else { return }
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
            // Short fade in/out avoids clicks.
            let envelope = min(1, min(t, 1 - t) * 12)
            channel[n] = Float(sin(phase) * 0.28 * envelope)
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
        player.scheduleBuffer(output, completionCallbackType: .dataPlayedBack) { _ in
            onPlayed()
        }
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
