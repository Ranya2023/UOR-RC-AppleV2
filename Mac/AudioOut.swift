import AVFoundation

/// Plays the sound the phone sends (the 🎤 microphone during the document camera).
final class AudioOut {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var started = false

    private func prepare(rate: Int, channels: Int) -> AVAudioFormat? {
        let wanted = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(rate),
                                   channels: AVAudioChannelCount(channels), interleaved: true)
        guard let wanted else { return nil }
        if format?.sampleRate == wanted.sampleRate && format?.channelCount == wanted.channelCount { return format }
        stop()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: wanted)
        do { try engine.start() } catch { return nil }
        player.play()
        started = true
        format = wanted
        return wanted
    }

    func play(base64: String, rate: Int, channels: Int) {
        guard let data = Data(base64Encoded: base64), !data.isEmpty,
              let fmt = prepare(rate: rate <= 0 ? 16000 : rate, channels: channels) else { return }
        let frames = AVAudioFrameCount(data.count / (2 * channels))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        data.withUnsafeBytes { raw in
            if let src = raw.baseAddress, let dst = buffer.int16ChannelData?[0] {
                memcpy(dst, src, data.count)
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stop() {
        if started { player.stop(); engine.stop(); started = false }
    }
}
