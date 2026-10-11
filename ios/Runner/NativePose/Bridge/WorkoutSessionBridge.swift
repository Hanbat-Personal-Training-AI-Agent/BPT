import AVFoundation
import Foundation
#if canImport(Flutter)
import Flutter
#endif

// App bridge for the workout camera (channel `bpt/native_pose_camera/<viewId>`):
//
//   native → Flutter  onPoseUpdate {rep, status, done}
//                     onFeedback  {key, n?, scope: "rep"|"set"}  → Flutter replies {text, lang} (or null);
//                                                                  the reply is what WorkoutVoice says
//                     onSetEnd    {setIndex, videoLocalPath?, worstJoint?}
//   Flutter → native  setVoiceMuted {muted}, startSet {setIndex}, endSet {setIndex}
//
// Line texts live only in lib/features/workout/data/kori_feedback_lines.dart: Flutter renders the
// line ({n}, locale) when it handles onFeedback and returns it, so there is no native copy.
// Everything above the `#if canImport(Flutter)` part is Foundation/AVFoundation only and is unit
// tested through ios/CalibrationEngineKit (symlink).

// MARK: - Key → joint (worstJoint)

enum FeedbackJoint {
    /// Joint per warning key (onSetEnd `worstJoint`: knee, hip, back, elbow, shoulder, head).
    /// Setup / tracking / praise / summary keys have none.
    static let byKey: [String: String] = [
        "pushup_hip_sag": "hip",
        "pushup_hip_pike": "hip",
        "pushup_shallow": "elbow",
        "pushup_no_lockout": "elbow",
        "pushup_head_drop": "head",
        "pushup_head_up": "head",
        "pushup_hand_position": "shoulder",
        "pushup_depth_fade": "elbow",
        "squat_hips_first": "hip",
        "squat_shallow": "knee",
        "squat_no_lockout": "knee",
        "squat_lean_drift": "back",
        "squat_depth_fade": "knee",
        "squat_knee_valgus": "knee",
        "squat_heel_rise": "knee",
        "row_torso_swing": "back",
        "row_standing_up": "back",
        "row_short_pull": "elbow",
        "row_head_up": "head",
        "row_shrug": "shoulder",
        "bench_hips_up": "hip",
        "bench_shallow": "elbow",
        "bench_no_lockout": "elbow",
        "deadlift_hips_first": "hip",
        "deadlift_no_lockout": "hip",
        "deadlift_lean_back": "back",
    ]

    /// Joint of the set's most frequent warning key (reps it fired in), counting only keys that are
    /// switched on (`enabledFeedbackKeys`: unvalidated keys never reach the user). Ties go to the
    /// first key in rule order (higher grade first). nil when no such key fired.
    static func worst(setCounts: [String: Int], enabled: Set<String>, ruleOrder: [String]) -> String? {
        var best: (key: String, count: Int)?
        for key in ruleOrder where enabled.contains(key) && byKey[key] != nil {
            if let count = setCounts[key], count > 0, count > (best?.count ?? 0) { best = (key, count) }
        }
        return best.flatMap { byKey[$0.key] }
    }
}

// MARK: - Voice queue

struct WorkoutVoiceLine: Equatable {
    let key: String
    let n: Int?
    let text: String
    let language: String
    let enqueuedAt: TimeInterval
}

/// Who speaks when: ★ (우선 grade, `interrupts`) cuts the current line and plays at once; other
/// lines play when idle, else wait in order and are dropped once they have waited > `maxWait` s.
struct WorkoutVoiceQueue {
    var maxWait: TimeInterval = 3
    private(set) var pending: [WorkoutVoiceLine] = []

    static func interrupts(_ key: String) -> Bool {
        FormWarningTracker.allKeys.contains(key) && FormWarningTracker.grade(of: key) == .priority
    }

    /// The line to play now (stop whatever is playing first), or nil when it was queued.
    mutating func push(_ line: WorkoutVoiceLine, isPlaying: Bool) -> WorkoutVoiceLine? {
        if Self.interrupts(line.key) || !isPlaying { return line }
        pending.append(line)
        return nil
    }

    /// After a line finished: the next one that has not waited too long.
    mutating func next(now: TimeInterval) -> WorkoutVoiceLine? {
        pending.removeAll { now - $0.enqueuedAt > maxWait }
        return pending.isEmpty ? nil : pending.removeFirst()
    }

    mutating func clear() { pending = [] }
}

/// Bundled recording for a line: `<key>_<n>.mp3` when n is set, then `<key>.mp3`. Lines with {n}
/// only get numbered files, so a missing number falls through to TTS.
func workoutVoiceAudioNames(key: String, n: Int?) -> [String] {
    (n.map { ["\(key)_\($0)"] } ?? []) + [key]
}

// MARK: - Voice

/// In-workout Kori voice (same shape as CalibrationVoice). Main thread only. Plays
/// `assets/kori_voice/<name>.mp3` (Korean) when the app has it, else AVSpeechSynthesizer.
final class WorkoutVoice: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var queue = WorkoutVoiceQueue()
    private let audioURL: (String) -> URL?
    private(set) var muted = false
    /// Last line started (tests / debugging).
    private(set) var lastStarted: WorkoutVoiceLine?

    init(audioURL: @escaping (String) -> URL? = WorkoutVoice.bundledAudioURL) {
        self.audioURL = audioURL
        super.init()
        synthesizer.delegate = self
    }

    var isPlaying: Bool { player?.isPlaying == true || synthesizer.isSpeaking }

    func activate() {
        #if os(iOS)
        // .playback: audible on silent mode (the phone is propped up across the room).
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
        #endif
    }

    func say(key: String, n: Int?, text: String, language: String,
             now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !muted, !text.isEmpty else { return }
        let line = WorkoutVoiceLine(key: key, n: n, text: text, language: language, enqueuedAt: now)
        if let line = queue.push(line, isPlaying: isPlaying) {
            stopCurrent()
            play(line)
        }
    }

    func setMuted(_ value: Bool) {
        muted = value
        if value {
            queue.clear()
            stopCurrent()
        }
    }

    func stop() {
        queue.clear()
        stopCurrent()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func stopCurrent() {
        player?.stop()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func play(_ line: WorkoutVoiceLine) {
        lastStarted = line
        if line.language.hasPrefix("ko") {
            for name in workoutVoiceAudioNames(key: line.key, n: line.n) {
                if let url = audioURL(name), let player = try? AVAudioPlayer(contentsOf: url) {
                    player.delegate = self
                    player.play()
                    self.player = player
                    return
                }
            }
        }
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = AVSpeechSynthesisVoice(language: line.language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synthesizer.speak(utterance)
    }

    private func playNext() {
        if !muted, let line = queue.next(now: ProcessInfo.processInfo.systemUptime) { play(line) }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        self.player = nil
        playNext()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        playNext()
    }

    /// Flutter asset `assets/kori_voice/<name>.mp3` inside the app bundle (nil outside the app).
    static func bundledAudioURL(_ name: String) -> URL? {
        #if canImport(Flutter)
        let key = FlutterDartProject.lookupKey(forAsset: "assets/kori_voice/\(name).mp3")
        return Bundle.main.url(forResource: key, withExtension: nil)
        #else
        return nil
        #endif
    }
}

// MARK: - Debug flags

/// Launch-time switches: environment (`xcrun devicectl device process launch --environment-variables`)
/// or UserDefaults (launch argument `-BPTPerfLog YES`).
enum WorkoutDebugFlags {
    private static func flag(_ env: String, _ defaultsKey: String) -> Bool {
        ProcessInfo.processInfo.environment[env] == "1" || UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// One JSON line per second (pose FPS, drops, thermal, battery, recording) under workout_form_logs.
    static var perfLog: Bool { flag("BPT_PERF_LOG", "BPTPerfLog") }

    /// Per-set video. OFF until the on-device FPS check (recording ON vs OFF) shows a drop ≤ 10 %
    /// (docs/research/set_recording_perf.md); while off, onSetEnd sends videoLocalPath = null.
    static var setRecording: Bool { flag("BPT_SET_RECORDING", "BPTSetRecording") }
}

// MARK: - Per-set recording

/// Writes the pose-estimation frames (the same sample buffers, no second camera session) to one
/// H.264 .mp4 per set in Documents/workout_videos. Call from the camera processing queue only.
final class WorkoutSetRecorder {
    /// Files kept (newest first by name). 20 ≈ two full workouts (2 exercises × 5 sets); at
    /// 2.5 Mbit/s a 1-minute set is ~19 MB, so ≤ ~0.4 GB on the phone.
    static let keepFiles = 20
    static let bitRate = 2_500_000

    let url: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var failed = false

    init(url: URL) {
        self.url = url
    }

    static func directory() -> URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("workout_videos", isDirectory: true)
    }

    /// `<yyyyMMdd_HHmmss>_<exercise>_set<k>.mp4`: names sort by time.
    static func fileName(exercise: String, setIndex: Int, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "\(formatter.string(from: date))_\(exercise)_set\(setIndex).mp4"
    }

    /// Deletes the oldest .mp4 files so that at most `keep` remain.
    static func prune(directory: URL, keep: Int) {
        let fileManager = FileManager.default
        let files = ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".mp4") }.sorted()
        for name in files.dropLast(max(keep, 0)) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard !failed else { return }
        if writer == nil {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: CVPixelBufferGetWidth(pixelBuffer),
                    AVVideoHeightKey: CVPixelBufferGetHeight(pixelBuffer),
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Self.bitRate],
                ])
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { throw CocoaError(.featureUnsupported) }
                writer.add(input)
                guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.writer = writer
                self.input = input
            } catch {
                failed = true
                return
            }
        }
        if let input, input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }

    /// Closes the file; completion gets its URL, or nil when nothing was written or writing failed.
    func finish(_ completion: @escaping (URL?) -> Void) {
        guard let writer, let input, writer.status == .writing else {
            writer?.cancelWriting()
            completion(nil)
            return
        }
        input.markAsFinished()
        let url = url
        writer.finishWriting { completion(writer.status == .completed ? url : nil) }
    }
}

// MARK: - Perf log

/// Debug "perf log" (`WorkoutDebugFlags.perfLog`): every second one JSON line with pose FPS,
/// dropped camera frames, thermal state, battery level and recording on/off, in
/// Documents/workout_form_logs/perf_<time>.jsonl. Counters may be bumped from any thread.
final class WorkoutPerfLog {
    private let lock = NSLock()
    private var processed = 0
    private var dropped = 0
    private var lastFlush: TimeInterval
    private let handle: FileHandle
    let url: URL

    init?(exercise: String, rootDirectory: URL? = nil, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let fileManager = FileManager.default
        guard let root = rootDirectory ?? (try? fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                                                 appropriateFor: nil, create: true)
            .appendingPathComponent("workout_form_logs", isDirectory: true)) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        url = root.appendingPathComponent("perf_\(exercise)_\(formatter.string(from: Date())).jsonl")
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try Data().write(to: url)
            handle = try FileHandle(forWritingTo: url)
        } catch {
            return nil
        }
        lastFlush = now
    }

    func frameProcessed() { lock.lock(); processed += 1; lock.unlock() }
    func frameDropped() { lock.lock(); dropped += 1; lock.unlock() }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    /// Writes one line covering the time since the last flush and resets the counters.
    @discardableResult
    func flush(now: TimeInterval = ProcessInfo.processInfo.systemUptime,
               thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
               battery: Float, recording: Bool) -> [String: Any] {
        lock.lock()
        let p = processed, d = dropped
        processed = 0
        dropped = 0
        lock.unlock()
        let span = max(now - lastFlush, 1e-3)
        lastFlush = now
        let line: [String: Any] = [
            "t": Date().timeIntervalSince1970,
            "pose_fps": (Double(p) / span * 10).rounded() / 10,
            "dropped_frames": d,
            "thermal": Self.thermalName(thermal),
            "battery": battery < 0 ? NSNull() as Any : (Double(battery) * 100).rounded() / 100,
            "recording": recording,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) {
            try? handle.write(contentsOf: data + Data("\n".utf8))
        }
        return line
    }

    func close() { try? handle.close() }
}

// MARK: - Channel

#if canImport(Flutter)
/// The per-view channel: sends pose / feedback / set-end events, takes setVoiceMuted, startSet,
/// endSet, and says every feedback line Flutter renders back. Main thread only.
final class WorkoutChannel {
    let channel: FlutterMethodChannel
    let voice = WorkoutVoice()
    var onStartSet: ((Int) -> Void)?
    var onEndSet: ((Int) -> Void)?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        voice.activate()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(nil) }
            let args = call.arguments as? [String: Any]
            switch call.method {
            case "setVoiceMuted":
                self.voice.setMuted(args?["muted"] as? Bool ?? false)
            case "startSet":
                if let index = (args?["setIndex"] as? NSNumber)?.intValue { self.onStartSet?(index) }
            case "endSet":
                if let index = (args?["setIndex"] as? NSNumber)?.intValue { self.onEndSet?(index) }
            default:
                return result(FlutterMethodNotImplemented)
            }
            result(nil)
        }
    }

    func sendUpdate(rep: Int, status: String, done: Bool) {
        channel.invokeMethod("onPoseUpdate", arguments: ["rep": rep, "status": status, "done": done])
    }

    /// {key, n?, scope}. Flutter answers {text, lang} for a line it showed / keeps; that is spoken.
    func sendFeedback(_ event: FormFeedbackEvent) {
        var arguments: [String: Any] = ["key": event.key, "scope": event.scope.rawValue]
        if let n = event.n { arguments["n"] = n }
        channel.invokeMethod("onFeedback", arguments: arguments) { [weak self] reply in
            guard let reply = reply as? [String: Any], let text = reply["text"] as? String else { return }
            self?.voice.say(key: event.key, n: event.n, text: text, language: reply["lang"] as? String ?? "ko-KR")
        }
    }

    func sendSetEnd(setIndex: Int, videoLocalPath: String?, worstJoint: String?) {
        channel.invokeMethod("onSetEnd", arguments: [
            "setIndex": setIndex,
            "videoLocalPath": videoLocalPath.map { $0 as Any } ?? NSNull(),
            "worstJoint": worstJoint.map { $0 as Any } ?? NSNull(),
        ])
    }

    func close() {
        channel.setMethodCallHandler(nil)
        voice.stop()
    }
}
#endif
