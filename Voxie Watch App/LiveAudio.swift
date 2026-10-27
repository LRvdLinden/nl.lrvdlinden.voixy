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

    init() {
        playback.attach(player)
        playback.connect(player, to: playback.mainMixerNode, format: floatFormat)
    }

    func prepare() throws {
        let session = AVAudioSession.sharedInstance()
        #if os(iOS)
        // Walkietalkie audio should play from the iPhone speaker by default.
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.defaultToSpeaker, .allowBluetooth])
        #else
        // watchOS routes audio to the Watch speaker or connected audio device.
        try session.setCategory(.playAndRecord, mode: .voiceChat)
        #endif
        try session.setActive(true)
        if !playback.isRunning { try playback.start() }
        if !player.isPlaying { player.play() }
    }

    func startCapture(onChunk: @escaping @Sendable (Data) -> Void) throws {
        guard !capturing else { return }
        try prepare()
        let node = capture.inputNode
        let native = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: native, to: pcmFormat) else {
            throw AudioProblem.converter
        }
        let targetFormat = pcmFormat
        // ~170 ms at 48 kHz: avoids flooding HTTPS with tiny sub-50 ms uploads.
        node.installTap(onBus: 0, bufferSize: 8192, format: native) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / native.sampleRate + 128)
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
    }

    func play(_ pcm: Data, onPlayed: @escaping @Sendable () -> Void) throws {
        guard pcm.count >= 2, pcm.count.isMultiple(of: 2) else { return }
        try prepare()
        let count = pcm.count / 2
        guard let output = AVAudioPCMBuffer(pcmFormat: floatFormat,
                                           frameCapacity: AVAudioFrameCount(count)),
              let channel = output.floatChannelData?[0] else { return }
        output.frameLength = AVAudioFrameCount(count)
        pcm.withUnsafeBytes { bytes in
            guard let source = bytes.bindMemory(to: Int16.self).baseAddress else { return }
            for n in 0..<count { channel[n] = Float(source[n]) / 32768 }
        }
        player.scheduleBuffer(output, completionCallbackType: .dataPlayedBack) { _ in
            onPlayed()
        }
    }
}

private enum AudioProblem: LocalizedError {
    case converter
    var errorDescription: String? { "Audioformaat niet ondersteund" }
}
