import AVFoundation
import XCTest
@testable import CalibrationEngineKit

final class WorkoutSessionBridgeTests: XCTestCase {
    /// (key, kind) pairs from lib/features/workout/data/kori_feedback_lines.dart, the key source of truth.
    private func dartLines() throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("lib/features/workout/data/kori_feedback_lines.dart")
        let source = try String(contentsOf: url, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"key:\s*'([a-z_]+)',\s*kind:\s*KoriFeedbackKind\.(\w+)"#)
        var lines: [String: String] = [:]
        for m in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            lines[String(source[Range(m.range(at: 1), in: source)!])] = String(source[Range(m.range(at: 2), in: source)!])
        }
        XCTAssertGreaterThanOrEqual(lines.count, 28, "parsed the dart line table")
        return lines
    }

    func testSwiftKeysMatchDartLines() throws {
        let dart = try dartLines()
        // Every key native can send has a line in the dart file.
        XCTAssertEqual(FormWarningTracker.allKeys.subtracting(dart.keys), [])
        // Every rule key is a warning there, every warning has a joint and nothing else does.
        for (exercise, rules) in FormWarningTracker.rules {
            for rule in rules where rule.key != "setup_side_view" {
                XCTAssertEqual(dart[rule.key], "warning", "\(exercise) \(rule.key)")
            }
        }
        XCTAssertEqual(Set(FeedbackJoint.byKey.keys), Set(dart.filter { $0.value == "warning" }.keys))
        XCTAssertEqual(Set(FeedbackJoint.byKey.values).subtracting(["knee", "hip", "back", "elbow", "shoulder", "head"]), [])
    }

    func testWorstJoint() {
        let order = (FormWarningTracker.rules[.squat] ?? []).map(\.key)
        let all = FormWarningTracker.allKeys
        XCTAssertEqual(FeedbackJoint.worst(setCounts: ["squat_shallow": 2, "squat_lean_drift": 3], enabled: all, ruleOrder: order), "back")
        XCTAssertEqual(FeedbackJoint.worst(setCounts: ["squat_shallow": 2, "squat_lean_drift": 3], enabled: ["squat_shallow"], ruleOrder: order),
                       "knee", "keys that are off do not count")
        XCTAssertEqual(FeedbackJoint.worst(setCounts: ["squat_shallow": 2, "squat_hips_first": 2], enabled: all, ruleOrder: order),
                       "hip", "tie: rule order")
        XCTAssertNil(FeedbackJoint.worst(setCounts: [:], enabled: all, ruleOrder: order))
        XCTAssertNil(FeedbackJoint.worst(setCounts: ["setup_full_body": 4], enabled: all, ruleOrder: order + ["setup_full_body"]))
        // App default (no form key on) → always null today.
        XCTAssertNil(FeedbackJoint.worst(setCounts: ["squat_shallow": 5], enabled: FormCommonConfig().enabledFeedbackKeys, ruleOrder: order))
    }

    func testVoiceQueue() {
        func line(_ key: String, _ t: TimeInterval) -> WorkoutVoiceLine {
            WorkoutVoiceLine(key: key, n: nil, text: key, language: "ko-KR", enqueuedAt: t)
        }
        XCTAssertTrue(WorkoutVoiceQueue.interrupts("pushup_hip_sag"))
        XCTAssertTrue(WorkoutVoiceQueue.interrupts("squat_knee_valgus"))
        XCTAssertFalse(WorkoutVoiceQueue.interrupts("pushup_hip_pike"))
        XCTAssertFalse(WorkoutVoiceQueue.interrupts("tracking_lost"))
        XCTAssertFalse(WorkoutVoiceQueue.interrupts("unknown_key"))

        var q = WorkoutVoiceQueue()
        XCTAssertEqual(q.push(line("tracking_lost", 0), isPlaying: false)?.key, "tracking_lost", "idle: now")
        XCTAssertNil(q.push(line("praise_fixed", 0), isPlaying: true), "busy: queued")
        XCTAssertNil(q.push(line("setup_full_body", 2), isPlaying: true))
        XCTAssertEqual(q.push(line("row_torso_swing", 2.5), isPlaying: true)?.key, "row_torso_swing", "★ interrupts")
        XCTAssertEqual(q.next(now: 3.5)?.key, "setup_full_body", "waited 3.5 s: praise dropped")
        XCTAssertNil(q.next(now: 3.6))
        _ = q.push(line("praise_fixed", 10), isPlaying: true)
        q.clear()
        XCTAssertNil(q.next(now: 10))
    }

    func testVoiceAudioNamesAndMute() {
        XCTAssertEqual(workoutVoiceAudioNames(key: "pushup_no_lockout", n: 2), ["pushup_no_lockout_2", "pushup_no_lockout"])
        XCTAssertEqual(workoutVoiceAudioNames(key: "tracking_lost", n: nil), ["tracking_lost"])
        var asked: [String] = []
        let voice = WorkoutVoice(audioURL: { asked.append($0); return nil })
        voice.setMuted(true)
        voice.say(key: "tracking_lost", n: nil, text: "인식이 잠깐 끊겼어.", language: "ko-KR")
        XCTAssertNil(voice.lastStarted, "muted: nothing plays")
        XCTAssertEqual(asked, [])
    }

    func testSetRecorderWritesH264() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(WorkoutSetRecorder.fileName(exercise: "squat", setIndex: 1))
        let recorder = WorkoutSetRecorder(url: url)
        for i in 0..<15 { recorder.append(try sampleBuffer(width: 128, height: 96, frame: i)) }
        let done = expectation(description: "finish")
        var result: URL?
        recorder.finish { result = $0; done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(result, url)
        let asset = AVURLAsset(url: url)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        XCTAssertEqual(track.naturalSize, CGSize(width: 128, height: 96))
        XCTAssertEqual((track.formatDescriptions.first as! CMFormatDescription).mediaSubType, .h264)
        // Real-time input: frames arriving while the encoder is busy are skipped, like a late camera frame.
        XCTAssertGreaterThan(asset.duration.seconds, 0)

        // Nothing appended → nil, no file.
        let empty = WorkoutSetRecorder(url: dir.appendingPathComponent("empty.mp4"))
        let none = expectation(description: "empty")
        empty.finish { XCTAssertNil($0); none.fulfill() }
        wait(for: [none], timeout: 1)
    }

    func testRecordingFileNamesAndPrune() throws {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (2026, 10, 10, 9, 5, 7)
        let date = try XCTUnwrap(Calendar.current.date(from: c))
        XCTAssertEqual(WorkoutSetRecorder.fileName(exercise: "pushUp", setIndex: 3, date: date), "20261010_090507_pushUp_set3.mp4")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = ["20261001_100000_squat_set1.mp4", "20261003_100000_squat_set1.mp4", "20261002_100000_squat_set2.mp4", "notes.txt"]
        for name in names { try Data().write(to: dir.appendingPathComponent(name)) }
        WorkoutSetRecorder.prune(directory: dir, keep: 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(),
                       ["20261002_100000_squat_set2.mp4", "20261003_100000_squat_set1.mp4", "notes.txt"])
        XCTAssertEqual(WorkoutSetRecorder.keepFiles, 20)
    }

    func testPerfLogLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = try XCTUnwrap(WorkoutPerfLog(exercise: "squat", rootDirectory: dir, now: 100))
        for _ in 0..<30 { log.frameProcessed() }
        log.frameDropped()
        log.frameDropped()
        let first = log.flush(now: 101, thermal: .fair, battery: 0.55, recording: true)
        XCTAssertEqual(first["pose_fps"] as? Double, 30)
        XCTAssertEqual(first["dropped_frames"] as? Int, 2)
        XCTAssertEqual(first["thermal"] as? String, "fair")
        XCTAssertEqual(first["battery"] as? Double, 0.55)
        XCTAssertEqual(first["recording"] as? Bool, true)
        let second = log.flush(now: 103, thermal: .nominal, battery: -1, recording: false)
        XCTAssertEqual(second["pose_fps"] as? Double, 0, "counters reset")
        XCTAssertTrue(second["battery"] is NSNull, "unknown battery")
        log.close()
        let lines = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(parsed["pose_fps"] as? Double, 30)
        XCTAssertTrue(log.url.lastPathComponent.hasPrefix("perf_squat_"))
    }

    private func sampleBuffer(width: Int, height: Int, frame: Int) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        let pb = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(pb, [])
        memset(CVPixelBufferGetBaseAddress(pb), Int32(frame * 16 % 255), CVPixelBufferGetDataSize(pb))
        CVPixelBufferUnlockBaseAddress(pb, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: 30),
                                        decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: try XCTUnwrap(format),
                                                 sampleTiming: &timing, sampleBufferOut: &buffer)
        return try XCTUnwrap(buffer)
    }
}
