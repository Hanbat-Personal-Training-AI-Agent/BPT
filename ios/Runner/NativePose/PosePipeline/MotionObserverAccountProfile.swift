import Foundation
import CoreFoundation

/// Authenticated app-session association, not a claim of biometric identity or fit accuracy.
struct MotionObserverAccountProfile {
    let binding: String
    let sourceSession: Int
    let jobId: String
    let weight: Double
    let weightSource: String
    let ratios: [String: Double]
    let qualityEvidence: [String: Any]

    static func parse(_ payload: [String: Any], binding: String, sourceSession: Int) -> Self? {
        guard payload["schema"] as? String == "bpt.account-motion-profile.v1",
              payload["scope"] as? String == "same_account_live_camera_assumption",
              let job = payload["jobId"] as? String, !job.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, job.utf8.count <= 128,
              let declared = payload["engineeringWeight"] as? [String: Any],
              declared["meaning"] as? String == "explicit_engineering_weight_not_accuracy_probability",
              let weight = declared["value"] as? NSNumber, CFGetTypeID(weight) != CFBooleanGetTypeID(),
              weight.doubleValue.isFinite, weight.doubleValue > 0, weight.doubleValue <= 1,
              let source = declared["source"] as? String, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, source.utf8.count <= 512,
              let result = payload["calibration"] as? [String: Any],
              let version = result["schemaVersion"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let stub = result["stub"] as? NSNumber, CFGetTypeID(stub) == CFBooleanGetTypeID(), !stub.boolValue, result["bodyModel"] as? String == "smpl_neutral_v1.1.0",
              let beta = result["smplBeta"] as? [NSNumber], beta.count == 10,
              beta.allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite }),
              let bone = result["boneLengthData"] as? [String: Any], bone["unit"] as? String == "cm",
              bone["skeleton"] as? String == "h36m17", bone["pose"] as? String == "rest",
              let segments = bone["segments"] as? [String: Any],
              let quality = result["quality"] as? [String: Any] else { return nil }
        func nonnegative(_ value: Any?) -> Bool {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return false }
            return n.doubleValue.isFinite && n.doubleValue >= 0
        }
        var safeQuality: [String: Any] = [:]
        if let height = quality["heightErrorCm"], !(height is NSNull) {
            guard let n = height as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
            safeQuality["heightErrorCm"] = n.doubleValue
        }
        var safeViews: [String: [String: Any]] = [:]
        if let rawViews = quality["perView"] {
            guard let views = rawViews as? [String: [String: Any]] else { return nil }
            for (key, view) in views {
                if let error = view["reprojectionErrorPx"], !(error is NSNull) {
                    guard nonnegative(error), let n = error as? NSNumber else { return nil }
                    safeViews[key] = ["reprojectionErrorPx": n.doubleValue]
                } else { safeViews[key] = ["reprojectionErrorPx": NSNull()] }
            }
        }
        safeQuality["perView"] = safeViews
        guard nonnegative(safeQuality["heightErrorCm"]) || safeViews.values.contains(where: { nonnegative($0["reprojectionErrorPx"]) }) else { return nil }
        let excluded = Set(bone["appDefinitionDiffers"] as? [String] ?? [])
        var lengths: [String: Double] = [:]
        for name in BoneLengthConstraint.defaultSegments where !excluded.contains(name) {
            if let n = segments[name] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
               n.doubleValue.isFinite, n.doubleValue > 0, n.doubleValue < 200 { lengths[name] = n.doubleValue }
        }
        let legs = ["left", "right"].compactMap { side -> Double? in
            guard let a = lengths["\(side)_hip-\(side)_knee"], let b = lengths["\(side)_knee-\(side)_ankle"] else { return nil }
            return a+b
        }
        guard !legs.isEmpty else { return nil }
        let denominator = legs.reduce(0,+) / Double(legs.count)
        var ratios: [String: Double] = [:]
        for child in 1..<17 {
            if let length = lengths[BoneLengthConstraint.segmentNames[child-1]] {
                ratios["\(BoneLengthConstraint.parents[child])-\(child)"] = length/denominator
            }
        }
        guard !ratios.isEmpty else { return nil }
        return Self(binding: binding, sourceSession: sourceSession, jobId: job,
                    weight: weight.doubleValue, weightSource: source, ratios: ratios, qualityEvidence: safeQuality)
    }
}

/// Crosses MainActor/capture queues with immutable snapshots. A stale async payload
/// cannot repopulate a cleared binding after account/source/lifecycle invalidation.
final class MotionObserverAccountProfileGate: @unchecked Sendable {
    private let lock = NSLock()
    private var binding: String?
    private var profile: MotionObserverAccountProfile?
    private var consumed = false
    @discardableResult func begin(_ value: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        profile = nil; consumed = false
        guard !value.isEmpty, value.utf8.count <= 160 else { binding = nil; return false }
        binding = value; return true
    }
    func clear() { lock.lock(); defer { lock.unlock() }; profile = nil; binding = nil; consumed = false }
    func accept(_ args: [String: Any], sourceSession: Int?, enabled: Bool, isVideo: Bool) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        guard enabled, !isVideo else { profile = nil; return ["accepted": false, "reason": isVideo ? "recorded_video_profile_forbidden" : "disabled"] }
        guard let current = binding, args["binding"] as? String == current else { return ["accepted": false, "reason": "stale_binding"] }
        guard !consumed else { profile = nil; return ["accepted": false, "reason": "binding_already_consumed"] }
        consumed = true
        guard let session = sourceSession, session > 0, let payload = args["profile"] as? [String: Any],
              let parsed = MotionObserverAccountProfile.parse(payload, binding: current, sourceSession: session) else {
            profile = nil; return ["accepted": false, "reason": args["withheldReason"] as? String ?? "unverified_profile_or_source"]
        }
        profile = parsed; return ["accepted": true, "scope": "same_account_live_camera_assumption", "weightMeaning": "engineering_not_accuracy"]
    }
    func snapshot(session: Int?) -> MotionObserverAccountProfile? {
        lock.lock(); defer { lock.unlock() }
        guard let profile, profile.sourceSession == session else { return nil }
        return profile
    }
}
