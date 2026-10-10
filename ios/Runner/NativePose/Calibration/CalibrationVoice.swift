import AVFoundation
import Foundation

/// Korean speech (Kori's ElevenLabs voice, see [KoriSpeaker]), the capture chime and the
/// proximity beep. Main thread only.
///
/// The user cannot see the screen while showing their back, so for that view this is the only
/// channel. It therefore runs on a `.playback` audio session: system sounds and the default
/// session go quiet on silent mode, and a phone propped up for calibration is often on silent.
final class CalibrationVoice: NSObject {
    private let speaker = KoriSpeaker()
    private let config: CalibrationConfig.Voice
    private let tick = CalibrationVoice.tone(frequency: 880, duration: 0.06)
    private let chime = CalibrationVoice.tone(frequency: 1320, duration: 0.16)

    private var lastSpokenMessage: String?
    private var lastSpokenAt: TimeInterval = -.infinity
    private var lastBeepAt: TimeInterval = -.infinity
    private var releaseWhenIdle = false

    init(config: CalibrationConfig.Voice = CalibrationConfig.default.voice) {
        self.config = config
        super.init()
        speaker.onFinish = { [weak self] in self?.speakerDidFinish() }
    }

    func activate() {
        releaseWhenIdle = false
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
    }

    /// Speaks when the guidance changes, and repeats the same line every few seconds.
    func speak(_ guidance: CalibrationGuidance, now: TimeInterval) {
        let message = guidance.message
        let changed = message != lastSpokenMessage
        guard changed || now - lastSpokenAt >= repeatInterval(for: message) else { return }

        if !guidance.interrupts, speaker.isSpeaking {
            return
        }
        speaker.speak(message)
        lastSpokenMessage = message
        lastSpokenAt = now
    }

    /// `progress` is 0 (far from the target pose) to 1 (there); the beep interval shrinks with it.
    func beep(progress: Double, now: TimeInterval) {
        let clamped = min(max(progress, 0), 1)
        let interval = config.beepIntervalMax - (config.beepIntervalMax - config.beepIntervalMin) * clamped
        guard now - lastBeepAt >= interval else { return }
        lastBeepAt = now
        tick?.currentTime = 0
        tick?.play()
    }

    func playCaptureChime() {
        chime?.currentTime = 0
        chime?.play()
    }

    /// Stops at once (the user backed out).
    func stop() {
        speaker.stop()
        lastSpokenMessage = nil
        deactivate()
    }

    /// Lets the current line finish, then hands audio back to other apps.
    func deactivateWhenDone() {
        if speaker.isSpeaking {
            releaseWhenIdle = true
        } else {
            deactivate()
        }
    }

    private func speakerDidFinish() {
        if releaseWhenIdle, !speaker.isSpeaking {
            releaseWhenIdle = false
            deactivate()
        }
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Short lines repeat sooner than long ones so the user is not talked over constantly.
    private func repeatInterval(for message: String) -> TimeInterval {
        let span = config.repeatIntervalMax - config.repeatIntervalMin
        return config.repeatIntervalMin + span * min(1, Double(message.count) / 30.0)
    }

    /// A sine tone with short fades, as an in-memory WAV, so it plays through the playback session.
    private static func tone(frequency: Double, duration: Double) -> AVAudioPlayer? {
        let rate = 44_100.0
        let count = Int(rate * duration)
        let fade = Int(rate * 0.005)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let envelope = min(1, Double(min(i, count - 1 - i)) / Double(fade))
            samples[i] = Int16(sin(2 * .pi * frequency * Double(i) / rate) * envelope * 0.5 * Double(Int16.max))
        }
        var wav = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        let dataSize = UInt32(count * 2)
        wav.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize).littleEndian)
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)             // PCM, mono
        append(UInt32(rate).littleEndian); append(UInt32(rate * 2).littleEndian)     // rate, byte rate
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)              // block align, bits
        wav.append(contentsOf: Array("data".utf8)); append(dataSize.littleEndian)
        samples.withUnsafeBytes { wav.append(contentsOf: $0) }
        let player = try? AVAudioPlayer(data: wav)
        player?.prepareToPlay()
        return player
    }
}
