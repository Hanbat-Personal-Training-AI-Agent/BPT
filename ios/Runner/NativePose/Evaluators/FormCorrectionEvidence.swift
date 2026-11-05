import Foundation
import simd

/// Correction praise only. This never changes a rule result, delivery-assessed set, or generic encouragement.
struct FormCorrectionEvidence {
    struct Signature: Equatable {
        let source3D: Bool
        let side: FormSide
        let front: Bool
        let parameters: [Double]
        let reference: [Double]
        let baselineIDs: [Int]
    }
    let id: Int
    let source3D: Bool
    let side: FormSide?
    let front: Bool?
    let completeFields: Set<String>
    let eligibleRules: Set<String>
    let references: [String: [Double]]
    let parameters: [String: [Double]]

    init(id: Int, source3D: Bool, frames: [FormFrameSample], common: FormCommonConfig,
         pushUp: PushUpFormConfig, squat: SquatFormConfig, row: BarbellRowFormConfig,
         expectedFrameIDs: [Int]? = nil) {
        self.id=id;self.source3D=source3D
        let sourceComplete = !source3D || (expectedFrameIDs.map { $0 == frames.map(\.frame) } ?? false)
        side=frames.first.flatMap { first in frames.allSatisfy { $0.side == first.side } ? first.side : nil }
        front=frames.first.flatMap { first in
            guard let value=first.frontView,frames.allSatisfy({ $0.frontView == value && $0.correctionFields.contains("view") }) else { return nil }
            return value
        }
        let names=["hipDeviation","elbow","knee","torso","elbowBehind","earShoulder","headAngle",
                   "hipY","shoulderY","torsoLength","kneeAnkleGapRatio","heelToe"]
        func full(_ fields: [String], _ selected: [FormFrameSample]) -> Bool {
            !selected.isEmpty && selected.allSatisfy { frame in fields.allSatisfy { frame.correctionFields.contains($0) } }
        }
        completeFields=sourceComplete ? Set(names.filter { full([$0],frames) }) : []
        var rules=Set<String>()
        let requirements:[String:[String]]=[
            "pushup_hip_sag":["hipDeviation"],"pushup_hip_pike":["hipDeviation"],"pushup_shallow":["elbow"],
            "squat_shallow":["knee"],"squat_heel_rise":["heelToe"],
            "row_torso_swing":["torso"],"row_standing_up":["torso"],"row_short_pull":["elbowBehind"],
            "row_shrug":["headAngle","earShoulder"]]
        for (key,fields) in requirements where full(fields,frames) { rules.insert(key) }
        if full(["knee"],frames),let minimum=frames.compactMap(\.knee).min(),
           let bottom=frames.firstIndex(where:{ $0.knee == minimum }) {
            let window=Array(frames[bottom...].prefix(max(0,squat.hipsFirstWindowFrames)+1))
            // Complete endpoint search plus the actually consumed bottom normalization; no extra phase gate.
            if full(["torso","hipY","shoulderY"],window),frames[bottom].correctionFields.contains("torsoLength") {
                rules.insert("squat_hips_first")
            }
        }
        if full(["hipY"],frames),let maximum=frames.compactMap(\.hipY).max(),
           let bottom=frames.firstIndex(where:{ $0.hipY == maximum }),
           full(["kneeAnkleGapRatio"],Array(frames[bottom...])) { rules.insert("squat_knee_valgus") }
        eligibleRules=sourceComplete ? rules : []
        let shared=[common.minJointConfidence,common.frontViewShoulderRatio,common.frontViewRepFraction]
        parameters=[
            "pushup_hip_sag":shared+[pushUp.hipSagDeviation],"pushup_hip_pike":shared+[pushUp.hipPikeDeviation],
            "pushup_shallow":shared+[pushUp.shallowOverBaselineDegrees,Double(common.baselineRepCount)],
            "squat_hips_first":shared+[squat.hipsFirstTorsoRiseDegrees,Double(squat.hipsFirstWindowFrames)],
            "squat_knee_valgus":shared+[squat.valgusKneeAnkleGapRatio],
            "squat_shallow":shared+[squat.shallowOverBaselineDegrees,Double(common.baselineRepCount)],
            "squat_heel_rise":shared+[squat.heelRiseShinRatio,squat.footMinConfidence],
            "row_torso_swing":shared+[row.torsoSwingRangeDegrees],
            "row_standing_up":shared+[row.standingUpDegrees,Double(common.baselineRepCount)],
            "row_short_pull":shared+[row.shortPullBelowBaseline,Double(common.baselineRepCount)],
            "row_shrug":shared+[row.shrugEarShoulderDrop,row.shrugMaxHeadAngleChangeDegrees]]
        var refs=[String:[Double]]()
        for key in rules {
            let usesDirection=["squat_hips_first","row_torso_swing","row_standing_up","row_short_pull"].contains(key)
            let usesUp=(usesDirection && key != "row_short_pull") || key == "pushup_hip_sag" || key == "pushup_hip_pike"
            if source3D && usesUp {
                if let up=frames.first?.correctionUp,up.x.isFinite,up.y.isFinite,up.z.isFinite,
                   frames.allSatisfy({ $0.correctionUp == up }) { refs[key]=[up.x,up.y,up.z] }
            } else if !source3D && usesDirection {
                if let facing=frames.first?.correctionFacing,facing.isFinite,
                   frames.allSatisfy({ $0.correctionFacing == facing }) { refs[key]=[facing] }
            } else { refs[key]=[] }
        }
        references=refs
    }

    func signatures(history: [FormCorrectionEvidence], baselineCount: Int) -> [String:Signature] {
        guard let side,let front else { return [:] }
        let baselineFields=["pushup_shallow":"elbow","squat_shallow":"knee",
                            "row_standing_up":"torso","row_short_pull":"elbowBehind"]
        var output=[String:Signature]()
        for key in eligibleRules {
            guard front == (key == "squat_knee_valgus"),let params=parameters[key],params.allSatisfy(\.isFinite),
                  let reference=references[key] else { continue }
            var ids=[Int]()
            if let field=baselineFields[key] {
                guard baselineCount>0,history.count>=baselineCount else { continue }
                let consumed=history.prefix(baselineCount)
                guard consumed.allSatisfy({ old in
                    old.source3D == source3D && old.side == side && old.front == front &&
                    old.completeFields.contains(field) && old.parameters[key] == params && old.references[key] == reference
                }) else { continue }
                ids=consumed.map(\.id)
            }
            output[key]=Signature(source3D:source3D,side:side,front:front,parameters:params,reference:reference,baselineIDs:ids)
        }
        return output
    }

    static func finite2D(_ sample: FormFrameSample, pose: [PoseKeypoint], feet: FootKeypoints?,
                         common: FormCommonConfig, squat: SquatFormConfig, facing: Double?, facingTrusted: Bool) -> Set<String> {
        let j=FormGeometry.joints(sample.side)
        func good(_ ids: [Int]) -> Bool { ids.allSatisfy { i in
            let p=pose[i];return p.x.isFinite && p.y.isFinite && p.confidence.isFinite && p.confidence>=common.minJointConfidence
        } }
        let fields:[String:[Int]]=["hipDeviation":[j.hip,j.shoulder,j.ankle],"elbow":[j.shoulder,j.elbow,j.wrist],
            "knee":[j.hip,j.knee,j.ankle],"torso":[j.shoulder,j.hip],"elbowBehind":[j.elbow,j.shoulder,j.hip],
            "earShoulder":[j.ear,j.shoulder,j.hip],"headAngle":[0,j.ear],"hipY":[j.shoulder,j.hip],
            "shoulderY":[j.shoulder,j.hip],"torsoLength":[j.shoulder,j.hip],
            "kneeAnkleGapRatio":[5,6,11,12,13,14,15,16]]
        let measurements=sample.faultMeasurements
        var out=Set(fields.compactMap { field,ids -> String? in
            guard measurements[field]?.isFinite == true,good(ids) else { return nil }
            if ["torso","elbowBehind"].contains(field), !(good([0,j.ear]) && facing?.isFinite == true && facingTrusted) { return nil }
            return field
        })
        if good([5,6,11,12]),sample.frontView != nil,sample.shoulderRatio?.isFinite == true { out.insert("view") }
        if let feet,good([j.knee,j.ankle]),sample.heelToe?.isFinite == true {
            let pair=sample.side == .left ? [feet.leftHeel,feet.leftBigToe] : [feet.rightHeel,feet.rightBigToe]
            if pair.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.confidence.isFinite && $0.confidence>=squat.footMinConfidence }) {
                out.insert("heelToe")
            }
        }
        return out
    }

    /// Same constituent mapping as coco17ToH36M17, preserving each source joint's support rather than averaging scores.
    static func observedH36MJoints(_ pose: [PoseKeypoint], minimumConfidence: Double) -> Set<Int> {
        guard pose.count == 17,minimumConfidence.isFinite else { return [] }
        let constituents=[[11,12],[12],[14],[16],[11],[13],[15],[11,12,5,6],
                          [5,6],[0,5,6],[1,2],[5],[7],[9],[6],[8],[10]]
        return Set(constituents.indices.filter { i in constituents[i].allSatisfy { source in
            let p=pose[source]
            return p.x.isFinite && p.y.isFinite && p.confidence.isFinite && p.confidence>=minimumConfidence
        } })
    }

    static func finite3D(_ sample: FormFrameSample, pose: [SIMD3<Double>], like sample2D: FormFrameSample,
                         up: SIMD3<Double>) -> Set<String> {
        let j=FormGeometry.h36mSide(sample.side)
        let fields=["elbow":[j.shoulder,j.elbow,j.wrist],"knee":[j.hip,j.knee,j.ankle],
                    "torso":[0,8,1,4],"hipDeviation":[0,8,3,6],"elbowBehind":[j.elbow,0,8,1,4],
                    "kneeAnkleGapRatio":[1,4,2,5,3,6]]
        let measurements=sample.faultMeasurements
        var out=Set(fields.compactMap { field,ids -> String? in
            guard measurements[field]?.isFinite == true,
                  ids.allSatisfy({ sample2D.correctionObservedH36M.contains($0) &&
                      pose[$0].x.isFinite && pose[$0].y.isFinite && pose[$0].z.isFinite }) else { return nil }
            if ["torso","hipDeviation"].contains(field), !(up.x.isFinite && up.y.isFinite && up.z.isFinite) { return nil }
            return field
        })
        if sample2D.correctionFields.contains("view") { out.insert("view") }
        for field in ["hipY","shoulderY","torsoLength"] where sample2D.correctionFields.contains(field) && sample.faultMeasurements[field]?.isFinite == true { out.insert(field) }
        return out
    }
}
