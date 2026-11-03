import Foundation
import CryptoKit

/// Separate opt-in presentation proposals. A numeric candidate is not a diagnosis or validated fault.
struct CoachingCandidateProposal {
    typealias JSON=[String:Any]
    private var activeProposal:String?
    private var activeRule:String?
    private var activeCapture:String?
    private var activeBinding:String?
    private var activeSource:JSON?
    private var lastCapture:String?
    private var lastSourcePTS:Double?
    private var presentedAt:[String:Double]=[:]
    private func binding(_ frame:JSON)->String {
        let source=frame["source"] as? JSON ?? [:],context=frame["context"] as? JSON ?? [:]
        let keys:[Any]=[frame["captureId"] ?? NSNull(),frame["experimentID"] ?? NSNull(),frame["variant"] ?? NSNull(),source["epoch"] ?? NSNull(),context["source_kind"] ?? NSNull(),context["exercise"] ?? NSNull(),context["side"] ?? NSNull(),context["phase"] ?? NSNull(),context["rotation"] ?? NSNull(),context["size"] ?? NSNull(),context["source_mirrored"] ?? NSNull()]
        return String(describing:keys)
    }
    mutating func expireIfNeeded(_ frame:JSON,force:Bool=false)->JSON? {
        if force { lastCapture=nil;lastSourcePTS=nil;presentedAt=[:] }
        guard let proposal=activeProposal else {return nil}
        let context=frame["context"] as? JSON ?? [:]
        let rule=(frame["rules"] as? [JSON] ?? []).first {$0["id"] as? String == activeRule}
        let meaningful=rule.map { value in
            CoachingCandidateEngine.yes(value["configured"]) && ((value["meaning"] as? String == "deviation" && value["state"] as? String == "positive_evidence") || (value["meaning"] as? String == "desired_match" && value["state"] as? String == "negative_evidence"))
        } ?? false
        guard force || binding(frame) != activeBinding || frame["captureId"] as? String != activeCapture || CoachingCandidateEngine.yes(context["flush_tail"]) || !meaningful else {return nil}
        // Clear the identity the receiver actually displayed, before accepting a new source.
        let oldCapture = activeCapture, oldSource = activeSource
        let sourceChanged = force || binding(frame) != activeBinding
        activeProposal=nil;activeRule=nil;activeCapture=nil;activeBinding=nil;activeSource=nil
        if sourceChanged { lastCapture=nil;lastSourcePTS=nil;presentedAt=[:] }
        return ["schema":"bpt.coaching-candidate-clear.v1","captureId":oldCapture as Any? ?? NSNull(),"previousProposalId":proposal,"source":oldSource ?? [:],"reason":force ? "lifecycle_or_source_reset":"candidate_no_longer_supported","presentation":"visual_only_no_tts"]
    }
    mutating func next(_ frame:JSON)->JSON? {
        guard frame["authority"] as? String == "engineering_candidate_not_validated_form",
              let source=frame["source"] as? JSON,let context=frame["context"] as? JSON,
              !CoachingCandidateEngine.yes(context["flush_tail"]),
              let pts=CoachingCandidateEngine.number(source["source_pts"]),let index=CoachingCandidateEngine.integer(source["source_index"]),
              let experiment=frame["experimentID"] as? String,let captureID=frame["captureId"] as? String,let variant=frame["variant"] as? String else {return nil}
        let capture=binding(frame)
        if capture != lastCapture || lastSourcePTS.map({pts<=$0})==true {presentedAt=[:]}
        lastCapture=capture;lastSourcePTS=pts
        let supported:Set<String>=["pushup.camera_body_line_transfer","pushup.projected_arm_range","pushup.bottom_target","pushup.top_extension_target","squat.early_ascent_coordination","squat.bottom_target","squat.top_extension_target","row.camera_torso_window_transfer","row.phase_prefix_leg_arm_cooccurrence"]
        for rule in frame["rules"] as? [JSON] ?? [] {
            guard let id=rule["id"] as? String,supported.contains(id),CoachingCandidateEngine.yes(rule["configured"]) else {continue}
            let meaning=rule["meaning"] as? String,state=rule["state"] as? String
            let assessment:String
            if meaning=="deviation" && state=="positive_evidence" {assessment="deviation_candidate"}
            else if meaning=="desired_match" && state=="negative_evidence" {assessment="target_not_met_candidate"}
            else {continue}
            // Presentation cadence is separate from all evidence-duration/detection thresholds.
            if presentedAt[id].map({pts-$0<2})==true {continue}
            presentedAt[id]=pts
            let binding="\(capture)/\(index)/\(id)"
            let proposalID=SHA256.hash(data:Data(binding.utf8)).map {String(format:"%02x",$0)}.joined()
            activeProposal=proposalID;activeRule=id;activeCapture=captureID;activeBinding=capture;activeSource=source
            let components=rule["components"] as? [JSON] ?? []
            return ["schema":"bpt.coaching-candidate-proposal.v1","captureId":captureID,"proposalId":proposalID,"ruleId":id,"experimentID":experiment,"variant":variant,
                    "authority":"engineering_candidate_not_validated_form","assessment":assessment,"predicateMeaning":meaning!,"predicateState":state!,
                    "source":source,"context":context,"partialCoverage":CoachingCandidateEngine.yes(rule["partialCoverage"]),
                    "unresolvedComponents":components.filter {$0["state"] as? String == "unknown"}.count,"presentation":"visual_only_no_tts","delivery":"proposed"]
        }
        return nil
    }
}
