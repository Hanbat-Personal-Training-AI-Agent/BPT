import Foundation
import simd

/// Offline-only stateless uncertainty evidence. Never changes coordinates/targets/history.
enum BoneCorrectionReliability {
    static let maximumExpansion = 4.0 // one uncalibrated engineering bound; not clinical.
    struct SegmentEvidence {
        let name: String, parent: Int, child: Int
        let observed: Double?, output: Double?, absoluteLengthCorrection: Double?, expansion: Double?
        let status: String
        let reasons: [String]
    }
    struct Result {
        let segments: [SegmentEvidence]
        let existingInvalid: Set<Int>, additionalInvalid: Set<Int>, invalid: Set<Int>
        let globalReasons: [String]
    }
    static func subtree(_ joint: Int) -> Set<Int> {
        var result:Set<Int>=[],stack=[joint]
        while let k=stack.popLast() {result.insert(k);stack += (0..<17).filter{BoneLengthConstraint.parents[$0]==k}}
        return result
    }
    static func evaluate(raw:[SIMD3<Double>], segments:[String:BoneLengthConstraint.SegmentReport],
                         scale:Double?, existingInvalid:Set<Int>) -> Result {
        var proposed:Set<Int>=[],global=[String](),evidence=[SegmentEvidence]()
        guard raw.count==17,existingInvalid.allSatisfy({(0..<17).contains($0)}) else {
            return Result(segments:[],existingInvalid:existingInvalid,additionalInvalid:Set(0..<17).subtracting(existingInvalid),invalid:existingInvalid.union(0..<17),globalReasons:["unsupported_pose_or_mask_shape"])
        }
        for j in 0..<17 where !raw[j].x.isFinite || !raw[j].y.isFinite || !raw[j].z.isFinite {
            proposed.formUnion(subtree(j));global.append("unsupported_nonfinite_raw_joint_\(j)")
        }
        for child in 1..<17 {
            let name=BoneLengthConstraint.segmentNames[child-1]
            guard BoneLengthConstraint.defaultSegments.contains(name) else {continue}
            let parent=BoneLengthConstraint.parents[child],length=simd_length(raw[child]-raw[parent])
            var reasons=[String]();var observed:Double?,output:Double?,correction:Double?,ratio:Double?
            if !length.isFinite {reasons.append("unsupported_nonfinite_raw_segment")}
            else if length < BoneLengthConstraint.minBoneLength {reasons.append("unsupported_degenerate_raw_segment")}
            if scale == nil || !scale!.isFinite || scale!<=0 {reasons.append("unsupported_scale")}
            if let r=segments[name] {
                if r.observed.isFinite {observed=r.observed}
                if r.output.isFinite {output=r.output}
                if !r.observed.isFinite || r.observed<=0 {reasons.append("unsupported_report_observed")}
                else if length.isFinite && abs(length-r.observed)>1e-10*(1+length) {reasons.append("unsupported_inconsistent_observed")}
                if !r.output.isFinite || r.output<=0 {reasons.append("unsupported_report_output")}
                if r.targetCm == nil || !r.targetCm!.isFinite || r.targetCm!<=0 {reasons.append("unsupported_target")}
                if r.degenerate {reasons.append("unsupported_report_degenerate")}
                if !r.constrained {reasons.append("unsupported_not_constrained")}
                if let a=observed,let b=output {
                    let c=abs(b-a);if c.isFinite {correction=c}
                    if a>0 {let q=b/a;if q.isFinite {ratio=q} else {reasons.append("unsupported_expansion_overflow")}}
                }
            } else {reasons.append("unsupported_missing_segment_report")}
            let unsupported = !reasons.isEmpty
            if !unsupported,let ratio,ratio>maximumExpansion {reasons.append("expansion_above_4")}
            if !reasons.isEmpty {proposed.formUnion(subtree(child))}
            evidence.append(SegmentEvidence(name:name,parent:parent,child:child,observed:observed,output:output,absoluteLengthCorrection:correction,expansion:ratio,status:unsupported ? "unsupported":reasons.isEmpty ? "within_candidate_bound":"expansion_flagged",reasons:reasons))
        }
        return Result(segments:evidence,existingInvalid:existingInvalid,additionalInvalid:proposed.subtracting(existingInvalid),invalid:existingInvalid.union(proposed),globalReasons:global)
    }
}
