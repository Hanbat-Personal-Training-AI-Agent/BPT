import Foundation
import simd

/// Comparison-only port of the archived v4 experiment. Never read by an evaluator or overlay.
/// Missing source evidence is unavailable, not a guessed frame clock or contact observation.
struct ExerciseMotionObserver {
    struct Configuration {
        let exercise: String
        let variant: ExerciseMotionVariant
        let profile: ExerciseMotionCalibrationProfile?
        let fixedCameraAssertion: Bool
        var profileRequested = false
        var onlineCalibration = false

        static func parse(environment: [String: String], exercise: String,
                          isVideo: Bool) throws -> Self? {
            guard let selected = environment["BPT_MOTION_OBSERVER"], !selected.isEmpty else { return nil }
            guard let variant = ExerciseMotionVariant.environment(selected) else { return nil }
            let normalized = exercise.replacingOccurrences(of: "-", with: "_")
            guard ["pushup", "squat", "barbell_row"].contains(normalized) else { return nil }
            // No verified person/source ownership exists in this camera path.
            // Keep optional profile requests explicit but withheld; do not read
            // or apply somebody's prior profile based only on a capture counter.
            return Self(exercise: normalized, variant: variant, profile: nil,
                        fixedCameraAssertion: isVideo && environment["BPT_MOTION_OBSERVER_FIXED_CAMERA"] == "1",
                        profileRequested: !(environment["BPT_MOTION_OBSERVER_PROFILE"] ?? "").isEmpty,
                        onlineCalibration: environment["BPT_MOTION_OBSERVER_ONLINE_CALIBRATION"] == "1")
        }
    }

    final class SourceSession: @unchecked Sendable {
        private let lock = NSLock()
        private var generation = 0
        private var active = false
        func begin() { lock.lock(); defer { lock.unlock() }; generation += 1; active = true }
        func end() { lock.lock(); defer { lock.unlock() }; active = false }
        func snapshot() -> Int? { lock.lock(); defer { lock.unlock() }; return active ? generation : nil }
        func rotateIfCurrent(_ value: Int?) -> Int? {
            lock.lock(); defer { lock.unlock() }
            guard active, value == generation else { return nil }
            generation += 1; return generation
        }
        func accepts(_ value: Int?) -> Bool { guard let value else { return false }; return snapshot() == value }
    }

    struct Source {
        let session: Int
        let frame: Int
        let sourceIndex: Int?
        let pts: Double?
        let timeValue: Int64?
        let timeScale: Int32?
        let rotation: Int
        let width: Int
        let height: Int
        let isVideo: Bool
        var dictionary: [String: Any] {
            ["session": session, "frame": frame, "source_index": sourceIndex as Any? ?? NSNull(),
             "source_pts": pts.flatMap { $0.isFinite ? $0 : nil } as Any? ?? NSNull(),
             "source_time_value": timeValue as Any? ?? NSNull(), "source_time_scale": timeScale as Any? ?? NSNull(),
             "time_basis": "sample_pts_seconds", "rotation": rotation, "width": width, "height": height,
             "source_kind": isVideo ? "video_frame" : "camera_capture_index"]
        }
    }

    struct Output {
        let source: Source
        let raw: [SIMD3<Double>]
        let candidate: [SIMD3<Double>]?
        let correction: [Double]?
        let uncertainty: [Double]?
        let invalid: Set<Int>
        let variant: ExerciseMotionVariant
        let reasons: [String]
        let details: [String: Any]
        var dictionary: [String: Any] {
            func number(_ n: Double) -> Any { n.isFinite ? n : NSNull() }
            func pose(_ p: [SIMD3<Double>]) -> [[Any]] { p.map { [number($0.x), number($0.y), number($0.z)] } }
            return ["schema": "bpt.motion-observer.v1", "source": source.dictionary,
                    "authority": "experimental_comparison_no_feedback_adoption", "variant": variant.rawValue,
                    "coordinate_type": "original_xs_model_units", "raw": pose(raw),
                    "corrected": candidate.map(pose) as Any? ?? NSNull(),
                    "correction_magnitude": correction?.map(number) as Any? ?? NSNull(),
                    "uncertainty": uncertainty?.map(number) as Any? ?? NSNull(),
                    "invalid_for_assessment": (0..<17).map { invalid.contains($0) },
                    "adopted_for_pose": false, "adopted_for_feedback": false,
                    "reasons": reasons, "details": details]
        }
    }

    let configuration: Configuration
    private var estimator: ExerciseMotionEstimator
    private var coordinateKey: String?
    private var lastPTS: Double?
    private var lastIndex: Int?
    private var online = ExerciseMotionOnlineCalibration()
    private var onlineApplied = false
    init(configuration: Configuration) {
        self.configuration = configuration
        estimator = ExerciseMotionEstimator(exercise: configuration.exercise, variant: configuration.variant,
            boneProfile: nil, calibrationConfidence: 0)
    }
    mutating func reset() {
        estimator.reset(reason: "observer_source_reset")
        estimator.setBoneProfile([:], confidence: 0)
        online = ExerciseMotionOnlineCalibration(); onlineApplied = false
        coordinateKey = nil; lastPTS = nil; lastIndex = nil
    }
    mutating func update(raw: [SIMD3<Double>], screen2D: [SIMD3<Double>], modelToImageScale: Double,
                         source: Source, flush: Bool) -> Output {
        func unavailable(_ reason: String) -> Output {
            Output(source: source, raw: raw, candidate: nil, correction: nil, uncertainty: nil,
                   invalid: Set(0..<17), variant: configuration.variant, reasons: [reason], details: [:])
        }
        guard !flush else { reset(); return unavailable("flush_tail_not_fresh_observation") }
        guard raw.count == 17, screen2D.count == 17,
              modelToImageScale.isFinite, modelToImageScale > 0,
              let pts = source.pts, pts.isFinite, pts >= 0,
              let scale = source.timeScale, scale > 0, let value = source.timeValue,
              abs(Double(value) / Double(scale) - pts) < 1e-6,
              let index = source.sourceIndex, index >= 0, source.frame >= 0, source.session > 0,
              source.width > 0, source.height > 0 else {
            reset(); return unavailable("source_or_coordinate_evidence_missing")
        }
        let key = "\(source.session)/\(source.rotation)/\(source.width)/\(source.height)"
        if coordinateKey == key, (lastPTS.map { pts <= $0 } ?? false) || (lastIndex.map { index <= $0 } ?? false) {
            reset(); return unavailable("nonmonotonic_source")
        }
        if coordinateKey != key || (lastPTS.map { pts - $0 > 0.5 } ?? false) { reset() }
        coordinateKey = key; lastPTS = pts; lastIndex = index
        let root = raw[0]
        let normalized = raw.map { ($0 - root) * modelToImageScale }
        if configuration.onlineCalibration {
            online.observe(normalized, screen: screen2D)
            if !onlineApplied, !online.boneRatios.isEmpty {
                estimator.setBoneProfile(online.boneRatios, confidence: 0.4)
                onlineApplied = true
            }
        }
        // No person identity, grip or native phase is invented. H's phase is an
        // internal heuristic, explicitly distinguished from observed exercise phase.
        let result = estimator.update(raw: normalized, screen2D: screen2D, timestamp: pts,
            fixedCamera: configuration.fixedCameraAssertion, cameraMotion: false,
            personID: nil, phase: nil, gripConfirmed: false)
        var candidate = result.corrected.map { $0 / modelToImageScale + root }
        let exact = (result.diagnostics["observation_passthrough"] as? [Int] ?? []) +
                    (result.diagnostics["expired_prediction_fallback"] as? [Int] ?? [])
        for j in exact where raw.indices.contains(j) { candidate[j] = raw[j] }
        return Output(source: source, raw: raw, candidate: candidate,
            correction: zip(candidate, raw).map { simd_length($0 - $1) },
            uncertainty: result.uncertainty.map { $0 / modelToImageScale }, invalid: result.invalidForAssessment,
            variant: configuration.variant, reasons: [], details: ["phase": result.phase as Any? ?? NSNull(),
                "phase_source": "internal_heuristic_not_observed", "person_identity": "unknown",
                "contact_evidence": configuration.fixedCameraAssertion ? "fixed_camera_operator_assertion_only" : "unknown",
                "grip_confirmed": false, "personal_profile_applied": false,
                "roles": result.roles,
                "contacts": Dictionary(uniqueKeysWithValues: result.contacts.map { (String($0.key), $0.value) }),
                "used_prediction": result.usedPrediction,
                "observation_confidence_h36m": screen2D.map { $0.z.isFinite ? $0.z as Any : NSNull() },
                "source_2d_height_normalized": screen2D.map { p in [p.x, p.y, p.z].map { $0.isFinite ? $0 as Any : NSNull() } },
                "model_to_image_scale": modelToImageScale,
                "confidence_semantics": "retained_detector_scores_not_accuracy_probabilities",
                "online_profile_applied": onlineApplied, "online_profile_samples": online.samples,
                "online_profile_authority": "observed_proportions_not_correct_posture",
                "profile_status": configuration.profileRequested ? "withheld_identity_unverified" : "not_supplied",
                "estimator": result.diagnostics])
    }
}


/// Owned bounded JSONL output, available in ordinary live-camera mode too.
/// Never opens a prior log or writes preferences/workout records.
final class ExerciseMotionObserverLog {
    let url: URL
    private var handle: FileHandle?
    private var bytes = 0
    private var rows = 0
    private let maximumBytes: Int
    private let maximumRows: Int
    init(directory: URL, maximumBytes: Int = 16 * 1024 * 1024, maximumRows: Int = 10_000) throws {
        self.maximumBytes = maximumBytes; self.maximumRows = maximumRows
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("observer_\(UUID().uuidString).jsonl")
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        write(["type": "header", "schema": "bpt.motion-observer-log.v1",
               "adopted_for_pose": false, "adopted_for_feedback": false,
               "maximum_rows": maximumRows, "maximum_bytes": maximumBytes])
    }
    func write(_ value: [String: Any]) {
        guard let handle, let encoded = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys),
              encoded.count <= 24_576 else { return }
        guard rows < maximumRows, bytes + encoded.count + 1 <= maximumBytes else { close(); return }
        do { try handle.write(contentsOf: encoded + Data([10])); bytes += encoded.count + 1; rows += 1 }
        catch { close() }
    }
    func close() { try? handle?.close(); handle = nil }
    deinit { close() }
}
