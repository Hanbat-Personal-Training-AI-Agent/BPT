import Foundation

/// OFF-runtime offline engineering candidate. No joint coordinates or nominal FPS enter this API.
struct BoneTargetContinuity {
    static let halfLifeSeconds = 0.2
    static let maximumGapSeconds = 1.0

    struct Output {
        let source: String
        let originalTargets: [String: Double]
        let originalShape: [String: Double]?
        let filteredShape: [String: Double]?
        let status: String
        let alpha: Double?
    }
    private var shape: [String: Double]?
    private var previousTime: Double?
    private var profileEpoch: String?

    mutating func reset() { shape=nil; previousTime=nil; profileEpoch=nil }

    mutating func update(targets: [String: Double], sourceTime: Double?, source: String,
                         profileEpoch epoch: String, trackingValid: Bool = true) -> Output {
        func output(_ original: [String:Double]?, _ filtered: [String:Double]?, _ status: String, _ alpha: Double? = nil) -> Output {
            Output(source:source, originalTargets:targets, originalShape:original,
                   filteredShape:filtered, status:status, alpha:alpha)
        }
        guard trackingValid else { reset(); return output(nil,nil,"unsupported_tracking") }
        guard !epoch.isEmpty else { reset(); return output(nil,nil,"unsupported_profile_epoch") }
        guard let t=sourceTime, t.isFinite, t>=0 else { reset(); return output(nil,nil,"unsupported_source_time") }
        guard !targets.isEmpty, targets.values.allSatisfy({ $0.isFinite && $0>0 }) else {
            reset(); return output(nil,nil,"unsupported_target")
        }
        let total=targets.keys.sorted().reduce(0.0) { $0+targets[$1]! }
        guard total.isFinite, total>0 else { reset(); return output(nil,nil,"unsupported_target") }
        let original=targets.mapValues { $0/total }
        guard original.values.allSatisfy({ $0.isFinite && $0>0 }) else { reset(); return output(nil,nil,"unsupported_target") }
        // A changed caller-owned epoch starts a new profile before comparing its clock.
        let reason: String
        if profileEpoch != nil && profileEpoch != epoch { reason="reset_profile_epoch" }
        else if shape == nil { reason="initialized" }
        else if Set(shape!.keys) != Set(original.keys) { reason="reset_target_keys" }
        else {
            let dt=t-previousTime!
            guard dt>0 else { reset(); return output(original,nil,"unsupported_nonmonotonic_time") }
            if dt>Self.maximumGapSeconds { reason="reset_long_gap" }
            else {
                let alpha = -expm1(-log(2)*dt/Self.halfLifeSeconds)
                var next=original
                for key in original.keys { next[key]=shape![key]!+(original[key]!-shape![key]!)*alpha }
                let sum=next.keys.sorted().reduce(0.0) { $0+next[$1]! }
                next=next.mapValues { $0/sum }
                shape=next;previousTime=t;profileEpoch=epoch
                return output(original,next,"filtered",alpha)
            }
        }
        shape=original;previousTime=t;profileEpoch=epoch
        return output(original,original,reason,1)
    }
}
