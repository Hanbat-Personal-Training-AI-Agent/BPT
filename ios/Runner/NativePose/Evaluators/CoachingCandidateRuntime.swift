import Foundation

/// Explicit caller engineering configuration. Nil means the whole candidate branch is off.
enum CoachingCandidateRuntime {
    typealias JSON=[String:Any]
    static func configuration(environment:[String:String]) throws -> CoachingCandidateEngine.Configuration? {
        guard environment["BPT_EXPERIMENTAL_COACHING"]=="1",environment["BPT_EXPERIMENTAL_CRITERIA_CANDIDATE"]=="1" else { return nil }
        guard let id=environment["BPT_COACHING_CANDIDATE_EXPERIMENT_ID"],let source=environment["BPT_COACHING_CANDIDATE_SOURCE"],let at=environment["BPT_COACHING_CANDIDATE_DECLARED_AT"],let variant=environment["BPT_COACHING_CANDIDATE_VARIANT"] else { throw CoachingCriteria.ValidationError.invalid("explicit candidate experiment declaration required") }
        let keys:[String:String]=[
            "BPT_CANDIDATE_HIP_RATIO_CORRECTION":"support.maximumHipRatioCorrection",
            "BPT_CANDIDATE_JOINT_SCORE":"support.minimumJointScore",
            "BPT_CANDIDATE_ANGLE_CORRECTION":"support.maximumAngleCorrection",
            "BPT_CANDIDATE_SQUAT_ASCENT_SECONDS":"window.squatAscentSeconds",
            "BPT_CANDIDATE_ROW_WINDOW_SECONDS":"window.rowRangeSeconds",
            "BPT_CANDIDATE_ROW_KNEE_DELTA":"row.kneeExtensionLower",
            "BPT_CANDIDATE_ROW_ELBOW_DELTA":"row.elbowFlexionLower",
            "BPT_CANDIDATE_PUSHUP_ARM_UPPER":"pushup.projectedUpperArmUpper",
            "BPT_CANDIDATE_PUSHUP_BOTTOM_ELBOW_UPPER":"pushup.bottomElbowUpper",
            "BPT_CANDIDATE_PUSHUP_TOP_ELBOW_LOWER":"pushup.topElbowLower",
            "BPT_CANDIDATE_SQUAT_BOTTOM_KNEE_UPPER":"squat.bottomKneeUpper",
            "BPT_CANDIDATE_SQUAT_TOP_KNEE_LOWER":"squat.topKneeLower",
            "BPT_CANDIDATE_SQUAT_TOP_HIP_LOWER":"squat.topHipLower"]
        var overrides:JSON=[:],provenance:[String:String]=[:]
        for (key,name) in keys { if let supplied=environment[key] { guard let number=Double(supplied),number.isFinite else { throw CoachingCriteria.ValidationError.invalid("candidate parameter must be finite") };overrides[name]=number;provenance[name]="explicit caller environment "+key+"; "+source } }
        return try .init(experimentID:id,source:source,experimentDeclaredAt:at,variant:variant,overrides:overrides,provenance:provenance)
    }
    /// A source generation is captured before asynchronous XS work, independently of terminal capture.
    final class SourceSession: @unchecked Sendable {
        private let lock = NSLock()
        private var generation = 0
        private var active = false
        func begin() { lock.lock(); defer { lock.unlock() }; generation += 1; active = true }
        func end() { lock.lock(); defer { lock.unlock() }; active = false }
        func snapshot() -> Int? { lock.lock(); defer { lock.unlock() }; return active ? generation : nil }
        func accepts(_ value: Int?) -> Bool { guard let value else { return false }; return snapshot() == value }
    }
    struct Output {
        var candidate: JSON?
        var terminal: JSON?
        var proposal: JSON?
        var clear: JSON?
        var error: JSON?
    }
    /// One invocation per lifted frame. The terminal logger consumes this same result.
    struct Processor {
        private var engine = CoachingCandidateEngine()
        private var presenter = CoachingCandidateProposal()
        private var lastFrame: JSON = [:]
        mutating func reset() -> JSON? {
            engine = CoachingCandidateEngine()
            return presenter.expireIfNeeded(lastFrame, force: true)
        }
        mutating func process(_ frame: CoachingCandidateEngine.Frame,
                              configuration: Result<CoachingCandidateEngine.Configuration?, Error>,
                              includeRequests: Bool = false) -> Output {
            do {
                guard let config = try configuration.get() else { return Output(clear: reset()) }
                let candidate = try engine.update(frame, configuration: config, includeRequests: includeRequests)
                let terminal = try CoachingCandidateRuntime.compact(candidate)
                lastFrame = candidate
                let clear = presenter.expireIfNeeded(candidate)
                let proposal = presenter.next(candidate)
                return Output(candidate: candidate, terminal: terminal, proposal: proposal, clear: clear, error: nil)
            } catch {
                let clear = reset()
                return Output(clear: clear, error: ["schema": "bpt.core3-candidate-error.v1",
                    "reason": "invalid_configuration_or_candidate_evaluation", "source": frame.source, "delivered": false])
            }
        }
    }
    /// A child of video_runs owned only by this opt-in test. Never permits arbitrary paths or old-file removal.
    static func namespace(environment:[String:String]) throws -> String? {
        guard environment["BPT_EXPERIMENTAL_CRITERIA_CANDIDATE"]=="1",let namespace=environment["BPT_TERMINAL_NAMESPACE"] else { return nil }
        let allowed=CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard namespace.hasPrefix("coaching-candidate-"),namespace.utf8.count<=64,namespace.unicodeScalars.allSatisfy({allowed.contains($0)}) else { throw CoachingCriteria.ValidationError.invalid("invalid owned candidate namespace") }
        return namespace
    }
    /// Compact terminal payload: full actual membership remains available in native replay requests.
    static func compact(_ full:JSON) throws -> JSON {
        var result=full
        let rules=(full["rules"] as? [JSON] ?? []).map { input -> JSON in
            var rule=input
            rule["components"]=(input["components"] as? [JSON] ?? []).map { value -> JSON in
                var component=value
                if let proof=value["proof"] as? JSON {
                    let indices=proof["sourceIndices"] as? [Any] ?? [],pts=proof["sourcePTS"] as? [Any] ?? []
                    component["proof"]=["kind":proof["kind"] ?? NSNull(),"count":indices.count,"firstSourceIndex":indices.first ?? NSNull(),"lastSourceIndex":indices.last ?? NSNull(),"startPTS":pts.first ?? NSNull(),"endPTS":pts.last ?? NSNull(),"causal":true]
                }
                return component
            }
            return rule
        }
        result["rules"]=rules;result["requests"]=nil
        guard try JSONSerialization.data(withJSONObject:result).count<=24_576 else { throw CoachingCriteria.ValidationError.invalid("candidate terminal payload budget") }
        return result
    }
}
