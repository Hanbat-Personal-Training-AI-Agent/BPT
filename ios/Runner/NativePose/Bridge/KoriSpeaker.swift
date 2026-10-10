import AVFoundation
import Flutter
import Foundation

/// 코리 목소리(ElevenLabs "manbo")로 문장을 그때그때 합성해서 재생한다. Main thread only.
///
/// API 키는 Info.plist `ElevenLabsApiKey`(ios/Flutter/Secrets.xcconfig 의 `ELEVENLABS_API_KEY`)에서
/// 읽는다. 키가 없거나 요청이 실패하면 iOS 기본 한국어 음성으로 대신 말한다.
/// 같은 실행 중 다시 나온 문장은 메모리에 둔 음성을 다시 틀고, 파일로는 저장하지 않는다.
final class KoriSpeaker: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private static let voiceId = "ZZ4xhVcc83kZBfNIlIIz"
    private static let modelId = "eleven_flash_v2_5"
    private static let maxCachedLines = 64

    /// 재생이 끝나면 불린다 (중간에 [stop]으로 끊은 경우는 제외).
    var onFinish: (() -> Void)?

    private let apiKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ElevenLabsApiKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }()
    private let fallback = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var task: URLSessionDataTask?
    private var cache: [String: Data] = [:]
    /// [stop]이나 새 [speak]마다 올라가서, 늦게 도착한 이전 응답을 버리게 한다.
    private var generation = 0

    override init() {
        super.init()
        fallback.delegate = self
    }

    var isSpeaking: Bool {
        task != nil || player?.isPlaying == true || fallback.isSpeaking
    }

    /// 지금 말하던 것을 끊고 [text]를 말한다.
    func speak(_ text: String, language: String = "ko-KR") {
        stop()
        let current = generation

        if let data = cache[text] {
            play(data, text: text, language: language)
            return
        }
        guard let apiKey, let request = Self.request(text: text, apiKey: apiKey) else {
            print("[TTS] ElevenLabs 키 없음 → 기본 음성: \(text)")
            speakFallback(text, language: language)
            return
        }

        print("[TTS] 요청: \(text)")
        let startedAt = Date()
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, current == self.generation else { return }
                self.task = nil
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard error == nil, status == 200, let data, !data.isEmpty else {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? error?.localizedDescription ?? ""
                    print("[TTS] 실패 (\(status)) → 기본 음성: \(body)")
                    self.speakFallback(text, language: language)
                    return
                }
                let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                print("[TTS] 응답 200 (\(data.count) bytes, \(ms)ms)")
                if self.cache.count >= Self.maxCachedLines { self.cache.removeAll() }
                self.cache[text] = data
                self.play(data, text: text, language: language)
            }
        }
        task?.resume()
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        fallback.stopSpeaking(at: .immediate)
    }

    private func play(_ data: Data, text: String, language: String) {
        guard let player = try? AVAudioPlayer(data: data) else {
            speakFallback(text, language: language)
            return
        }
        player.delegate = self
        player.play()
        self.player = player
    }

    private func speakFallback(_ text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        fallback.speak(utterance)
    }

    private static func request(text: String, apiKey: String) -> URLRequest? {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)?output_format=mp3_44100_128"),
              let body = try? JSONSerialization.data(withJSONObject: ["text": text, "model_id": modelId])
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return request
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        self.player = nil
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }
}

/// 운동 화면(Flutter)이 코리 피드백 대사를 말하게 하는 채널 `bpt/kori_voice`.
///
/// - `speak` { text, language? }: 지금 말하던 것을 끊고 말한다.
/// - `stop`: 멈추고 오디오를 다른 앱에 돌려준다.
final class KoriVoiceChannel {
    private let channel: FlutterMethodChannel
    private let speaker = KoriSpeaker()
    private var sessionActive = false

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "bpt/kori_voice", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
        switch call.method {
        case "speak":
            let args = call.arguments as? [String: Any]
            guard let text = args?["text"] as? String, !text.isEmpty else {
                result(nil)
                return
            }
            activateSession()
            speaker.speak(text, language: args?["language"] as? String ?? "ko-KR")
            result(nil)
        case "stop":
            speaker.stop()
            deactivateSession()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 무음 모드여도 들리게 `.playback` 세션을 쓴다 (체형 촬영 음성과 같은 설정).
    private func activateSession() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
        sessionActive = true
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }
}
