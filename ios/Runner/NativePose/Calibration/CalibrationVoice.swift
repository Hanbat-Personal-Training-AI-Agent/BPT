import AudioToolbox
import AVFoundation
import Foundation

/// Korean speech, the shutter sound and the proximity beep.
///
/// The user cannot see the screen while facing away from the phone, so for the back
/// view this is the only channel: the beep interval shortens as they approach the target.
final class CalibrationVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private let config: CalibrationConfig.Voice

    private var lastSpokenMessage: String?
    private var lastSpokenAt: TimeInterval = -.infinity
    private var lastBeepAt: TimeInterval = -.infinity

    init(config: CalibrationConfig.Voice = CalibrationConfig.default.voice) {
        self.config = config
    }

    /// Speaks when the guidance changes, and repeats the same line every few seconds.
    func speak(_ guidance: CalibrationGuidance, now: TimeInterval) {
        let message = guidance.message
        let changed = message != lastSpokenMessage
        let repeatAfter = changed ? 0 : repeatInterval(for: message)
        guard changed || now - lastSpokenAt >= repeatAfter else { return }

        if guidance.interrupts {
            synthesizer.stopSpeaking(at: .immediate)
        } else if synthesizer.isSpeaking {
            return
        }
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synthesizer.speak(utterance)
        lastSpokenMessage = message
        lastSpokenAt = now
    }

    /// `progress` is 0 (far from the target pose) to 1 (there); the beep interval shrinks with it.
    func beep(progress: Double, now: TimeInterval) {
        let clamped = min(max(progress, 0), 1)
        let interval = config.beepIntervalMax
            - (config.beepIntervalMax - config.beepIntervalMin) * clamped
        guard now - lastBeepAt >= interval else { return }
        lastBeepAt = now
        AudioServicesPlaySystemSound(1103)  // short tick
    }

    func playShutter() {
        AudioServicesPlaySystemSound(1108)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        lastSpokenMessage = nil
    }

    /// Short lines repeat sooner than long ones so the user is not talked over constantly.
    private func repeatInterval(for message: String) -> TimeInterval {
        let span = config.repeatIntervalMax - config.repeatIntervalMin
        let lengthFactor = min(1, Double(message.count) / 30.0)
        return config.repeatIntervalMin + span * lengthFactor
    }
}
