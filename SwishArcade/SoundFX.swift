import AVFoundation

/// Tiny synthesized SFX — no audio assets, same spirit as the web build's
/// WebAudio synth. Each effect is rendered once into a PCM buffer at
/// launch and replayed through a shared player node.
final class SoundFX {
    static let shared = SoundFX()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private let sampleRate = 44100.0
    private(set) var enabled = true

    private init() {
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffers["set"] = render { t in // tile set "thock-pop"
            let f = 340.0 + 500.0 * t / 0.09
            return sin(2 * Double.pi * f * t) * exp(-t * 26) * 0.5
        }
        buffers["pop"] = render { t in
            sin(2 * Double.pi * (700 + 900 * t / 0.12) * t) * exp(-t * 18) * 0.4
        }
        buffers["wrong"] = render { t in
            (sin(2 * Double.pi * 150 * t) > 0 ? 0.25 : -0.25) * exp(-t * 9)
        }
        buffers["word"] = render { t in // three-note chime
            let notes = [523.25, 659.25, 783.99]
            let step = Int(t / 0.07)
            let f = notes[min(step, 2)]
            let lt = t - Double(step) * 0.07
            return sin(2 * Double.pi * f * lt) * exp(-lt * 10) * 0.35
        }
        buffers["combo"] = render { t in
            sin(2 * Double.pi * (500 + 1400 * t / 0.22) * t) * exp(-t * 6) * 0.35
        }
        buffers["bomb"] = render { t in
            let noise = Double.random(in: -1...1)
            return noise * exp(-t * 7) * 0.5 + sin(2 * Double.pi * 70 * t) * exp(-t * 8) * 0.5
        }
        buffers["win"] = render { t in // five-note jingle
            let notes = [523.25, 659.25, 783.99, 1046.5, 783.99]
            let step = Int(t / 0.11)
            let f = notes[min(step, 4)]
            let lt = t - Double(step) * 0.11
            return sin(2 * Double.pi * f * lt) * exp(-lt * 7) * 0.35
        }
        buffers["pickup"] = render { t in
            sin(2 * Double.pi * (900 - 500 * t / 0.08) * t) * exp(-t * 22) * 0.3
        }
        try? engine.start()
        player.play()
    }

    private func render(_ wave: (Double) -> Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(sampleRate * 0.6)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            data[i] = Float(wave(Double(i) / sampleRate))
        }
        return buffer
    }

    func play(_ name: String) {
        guard enabled, let buffer = buffers[name] else { return }
        if !engine.isRunning { try? engine.start() }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    func set() { play("set") }
    func pop() { play("pop") }
    func wrong() { play("wrong") }
    func word() { play("word") }
    func combo() { play("combo") }
    func bomb() { play("bomb") }
    func win() { play("win") }
    func pickup() { play("pickup") }
}
