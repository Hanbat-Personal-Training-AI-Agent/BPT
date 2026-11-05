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
        func revision() -> Int { lock.lock(); defer { lock.unlock() }; return generation }
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
        var profileBinding: String? = nil
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
    private var appliedAccountProfile: MotionObserverAccountProfile?
    init(configuration: Configuration) {
        self.configuration = configuration
        estimator = ExerciseMotionEstimator(exercise: configuration.exercise, variant: configuration.variant,
            boneProfile: nil, calibrationConfidence: 0)
    }
    mutating func reset() {
        estimator.reset(reason: "observer_source_reset")
        estimator.setBoneProfile([:], confidence: 0)
        online = ExerciseMotionOnlineCalibration(); onlineApplied = false; appliedAccountProfile = nil
        coordinateKey = nil; lastPTS = nil; lastIndex = nil
    }
    mutating func update(raw: [SIMD3<Double>], screen2D: [SIMD3<Double>], modelToImageScale: Double,
                         source: Source, flush: Bool, accountProfile: MotionObserverAccountProfile? = nil) -> Output {
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
        if let profile = accountProfile, !source.isVideo, profile.sourceSession == source.session,
           profile.binding == source.profileBinding {
            if appliedAccountProfile?.binding != profile.binding {
                estimator.reset(reason: "account_profile_binding")
                estimator.setBoneProfile(profile.ratios, confidence: profile.weight)
                appliedAccountProfile = profile
                online = ExerciseMotionOnlineCalibration(); onlineApplied = false
            }
        } else if appliedAccountProfile != nil {
            estimator.reset(reason: "account_profile_cleared"); estimator.setBoneProfile([:], confidence: 0)
            appliedAccountProfile = nil
            online = ExerciseMotionOnlineCalibration(); onlineApplied = false
        }
        let root = raw[0]
        let normalized = raw.map { ($0 - root) * modelToImageScale }
        if configuration.onlineCalibration && appliedAccountProfile == nil {
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
                "grip_confirmed": false, "personal_profile_bound": appliedAccountProfile != nil,
                "personal_profile_applied": appliedAccountProfile != nil && result.diagnostics["calibration_used"] as? Bool == true,
                "personal_profile_scope": appliedAccountProfile == nil ? "withheld" : "same_account_live_camera_assumption",
                "personal_profile_weight": appliedAccountProfile?.weight as Any? ?? NSNull(),
                "personal_profile_weight_source": appliedAccountProfile?.weightSource as Any? ?? NSNull(),
                "personal_profile_job_id": appliedAccountProfile?.jobId as Any? ?? NSNull(),
                "personal_profile_quality_evidence": appliedAccountProfile?.qualityEvidence as Any? ?? NSNull(),
                "roles": result.roles,
                "contacts": Dictionary(uniqueKeysWithValues: result.contacts.map { (String($0.key), $0.value) }),
                "used_prediction": result.usedPrediction,
                "observation_confidence_h36m": screen2D.map { $0.z.isFinite ? $0.z as Any : NSNull() },
                "source_2d_height_normalized": screen2D.map { p in [p.x, p.y, p.z].map { $0.isFinite ? $0 as Any : NSNull() } },
                "model_to_image_scale": modelToImageScale,
                "confidence_semantics": "retained_detector_scores_not_accuracy_probabilities",
                "online_profile_applied": onlineApplied, "online_profile_samples": online.samples,
                "online_profile_used_by_variant": onlineApplied && result.diagnostics["calibration_used"] as? Bool == true,
                "online_profile_authority": "observed_proportions_not_correct_posture",
                "profile_status": appliedAccountProfile != nil ? "account_session_bound_assumption" : (configuration.profileRequested ? "withheld_identity_unverified" : "not_supplied"),
                "estimator": result.diagnostics])
    }
}


/// Owned bounded JSONL output. Header/observation schemas stay v1; a footer is required
/// to establish completion. A missing footer (crash, disk failure) is always incomplete.
/// Called on the main actor by the camera owner; never read by pose/feedback code.
final class ExerciseMotionObserverLog {
    enum Reason: String {
        case normalDrain = "normal_drain"
        case explicitClose = "explicit_close"
        case cameraStop = "camera_stop"
        case background = "background"
        case captureInterrupted = "capture_interrupted"
        case deinitialized = "deinitialized"
        case rowLimit = "row_limit"
        case byteLimit = "byte_limit"
        case serializationFailure = "serialization_failure"
        case recordTooLarge = "record_too_large"
        case writeFailure = "write_failure"
        case flushFailure = "flush_failure"
        case processingFailure = "processing_failure"
        case stoppedGeneration = "stopped_generation"
        case unflushedTail = "unflushed_tail"
        case drainNotConfirmed = "drain_not_confirmed"
        case drainSuperseded = "drain_superseded"
        case missingObservation = "missing_observation"
        case invalidPendingFrames = "invalid_pending_frames"
    }
    enum Suppression: String {
        case stoppedGeneration = "stopped_generation"
        case flushTail = "flush_tail_not_fresh_observation"
        case noRawModelOutput = "no_raw_model_output"
        case unavailable = "missing_observation"
    }
    // Space for one bounded control record, even after a data cap is hit.
    private static let footerReserve = 2048
    let url: URL
    private var handle: FileHandle?
    private var bytes = 0
    private var rows = 0
    private var attempted = 0
    private var written = 0
    private var observations = 0
    private var rejected = 0
    private var suppressed: [String: Int] = [:]
    private var firstIssue: Reason?
    private let maximumBytes: Int
    private let maximumRows: Int
    private let writeData: (FileHandle, Data) throws -> Void

    init(directory: URL, maximumBytes: Int = 16 * 1024 * 1024, maximumRows: Int = 10_000,
         writeData: @escaping (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) }) throws {
        let header: [String: Any] = ["type": "header", "schema": "bpt.motion-observer-log.v1",
            "adopted_for_pose": false, "adopted_for_feedback": false,
            "maximum_rows": maximumRows, "maximum_bytes": maximumBytes,
            "completion_schema": "bpt.motion-observer-completion.v1", "completion_requires_footer": true]
        let data = try JSONSerialization.data(withJSONObject: header, options: .sortedKeys) + Data([10])
        guard maximumRows >= 2, maximumBytes >= data.count + Self.footerReserve else {
            throw NSError(domain: "ExerciseMotionObserverLog", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Limits must fit a header and completion footer"])
        }
        self.maximumBytes = maximumBytes; self.maximumRows = maximumRows; self.writeData = writeData
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("observer_\(UUID().uuidString).jsonl")
        try Data().write(to: url, options: .withoutOverwriting)
        let opened = try FileHandle(forWritingTo: url)
        do { try writeData(opened, data) }
        catch { try? opened.close(); throw error }
        handle = opened; bytes = data.count; rows = 1
    }

    func write(_ value: [String: Any]) {
        guard let handle else { return }
        attempted += 1
        let encoded: Data
        do {
            guard JSONSerialization.isValidJSONObject(value) else { throw CocoaError(.propertyListWriteInvalid) }
            encoded = try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
        } catch { reject(.serializationFailure); return }
        guard encoded.count <= 24_576 else { reject(.recordTooLarge); return }
        guard rows < maximumRows - 1 else { reject(.rowLimit); return }
        guard encoded.count + 1 <= maximumBytes - Self.footerReserve - bytes else { reject(.byteLimit); return }
        do {
            try writeData(handle, encoded + Data([10]))
            bytes += encoded.count + 1; rows += 1; written += 1
            if value["schema"] as? String == "bpt.motion-observer.v1" { observations += 1 }
        } catch {
            // A failed write may have appended a partial line. Recover the last known
            // boundary before a best-effort incomplete footer; never claim success.
            try? handle.truncate(atOffset: UInt64(bytes))
            try? handle.seek(toOffset: UInt64(bytes))
            reject(.writeFailure)
        }
    }

    func recordSuppressed(_ reason: Suppression) {
        guard handle != nil else { return }
        suppressed[reason.rawValue, default: 0] += 1
        if reason == .stoppedGeneration { markIncomplete(.stoppedGeneration) }
        if reason == .unavailable { markIncomplete(.missingObservation) }
    }

    func markIncomplete(_ reason: Reason) {
        guard handle != nil, reason != .normalDrain else { return }
        if firstIssue == nil { firstIssue = reason }
    }

    /// Only the producer owner can confirm all queues have drained. Pending lookahead
    /// frames are explicit incomplete evidence, even when every emitted row was saved.
    func finish(drained: Bool, pendingFrames: Int = 0) {
        if !drained { markIncomplete(.drainNotConfirmed) }
        if pendingFrames < 0 { markIncomplete(.invalidPendingFrames) }
        else if pendingFrames > 0 { markIncomplete(.unflushedTail) }
        finalize(reason: .normalDrain, drained: drained, pendingFrames: max(0, pendingFrames))
    }

    func close(reason: Reason = .explicitClose) {
        markIncomplete(reason == .normalDrain ? .explicitClose : reason)
        finalize(reason: reason, drained: false, pendingFrames: 0)
    }

    private func reject(_ reason: Reason) {
        rejected += 1; markIncomplete(reason)
        finalize(reason: reason, drained: false, pendingFrames: 0)
    }

    private func finalize(reason: Reason, drained: Bool, pendingFrames: Int) {
        guard let handle else { return }
        self.handle = nil
        do { try handle.synchronize() }
        catch { if firstIssue == nil { firstIssue = .writeFailure } }
        let complete = drained && pendingFrames == 0 && firstIssue == nil
        var footer: [String: Any] = ["type": "footer", "schema": "bpt.motion-observer-completion.v1",
            "complete": complete, "incomplete": !complete,
            "reason": (firstIssue ?? reason).rawValue, "close_reason": reason.rawValue,
            "drained": drained, "pending_frames": pendingFrames,
            "data_rows_attempted": attempted, "data_rows_written": written,
            "observation_rows_written": observations, "data_rows_rejected": rejected,
            "suppressed_outputs": suppressed, "counts_scope": "through_footer",
            "rows_before_footer": rows, "bytes_before_footer": bytes,
            "adopted_for_pose": false, "adopted_for_feedback": false]
        if let data = try? JSONSerialization.data(withJSONObject: footer, options: .sortedKeys),
           data.count + 1 <= Self.footerReserve {
            // If the device cannot write this record, the absent/invalid footer is
            // the evidence of incompletion. Do not replace a prior run or retry forever.
            do { try writeData(handle, data + Data([10])) }
            catch {
                // A write can fail after appending bytes, including a whole success
                // footer. Remove it before attempting an explicitly failed footer.
                do {
                    try handle.truncate(atOffset: UInt64(bytes))
                    try handle.seek(toOffset: UInt64(bytes))
                    footer["complete"] = false; footer["incomplete"] = true
                    footer["reason"] = Reason.writeFailure.rawValue
                    if let failed = try? JSONSerialization.data(withJSONObject: footer, options: .sortedKeys),
                       failed.count + 1 <= Self.footerReserve {
                        try? writeData(handle, failed + Data([10]))
                    }
                } catch { /* No reliable footer can be persisted on this device. */ }
            }
        }
        try? handle.close()
    }
    deinit { close(reason: .deinitialized) }
}
