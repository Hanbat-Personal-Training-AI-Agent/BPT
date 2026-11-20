import Foundation
import simd

// Compiled beside the three unchanged production constraint sources. The only shim,
// FormWarningTracker.median, is extracted verbatim by run_constraints.py.
func flat(_ points: [SIMD3<Double>]) -> [Double] { points.flatMap { [$0.x,$0.y,$0.z] } }
let input = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String:Any]]
var outputs = [[String:Any]]()
for group in input {
    let exercise = group["exercise"] as! String
    var full = Pose3DConstraints(); full.reflectFlippedKnee = exercise == "squat"
    var bones = Pose3DConstraints(); bones.angleLimits=[]; bones.kneeClampDegrees=nil
    var angles = Pose3DConstraints(); angles.boneLengths=false; angles.reflectFlippedKnee=full.reflectFlippedKnee
    var prior = full; prior.calibrationTargetsCm=prior.priorLengths
    var continuity = BoneTargetContinuity()
    var candidate = full
    var previousTargets: [String:Double]? = nil
    var rows = [[String:Any]]()
    for frame in group["frames"] as! [[String:Any]] {
        if !(frame["tracking_valid"] as! Bool) { continuity.reset() }
        guard frame["apply"] as! Bool else { continue }
        let raw = frame["raw"] as! [Double]
        let points = stride(from:0,to:51,by:3).map { SIMD3<Double>(raw[$0],raw[$0+1],raw[$0+2]) }
        let targets = full.sessionTargets() ?? full.priorLengths
        let currentBone = BoneLengthConstraint.apply(points,targetsCm:targets)
        let previousBone = BoneLengthConstraint.apply(points,targetsCm:previousTargets ?? targets)
        let source = full.sessionTargets() == nil ? "prior" : "session"
        let filtered = continuity.update(targets:targets, sourceTime:frame["source_time"] as? Double, source:source, profileEpoch:exercise)
        guard let shape = filtered.filteredShape else { fatalError("unsupported candidate input: \(filtered.status)") }
        candidate.calibrationTargetsCm=shape
        let (candidateFixed,candidateReport) = candidate.apply(points)
        let (fixed,report) = full.apply(points)
        let bone = bones.apply(points).0, angle = angles.apply(points).0, fixedPrior = prior.apply(points).0
        rows.append(["frame":frame["frame"]!,"full":flat(fixed),"candidate":flat(candidateFixed),"candidate_invalid":candidateReport.invalidJoints.sorted(),"target_original":filtered.originalTargets,"target_original_shape":filtered.originalShape!,"target_filtered_shape":shape,"target_source":filtered.source,"target_filter_status":filtered.status,"source_time":frame["source_time"]!,"bone_only":flat(bone),"angle_only":flat(angle),"fixed_prior_full":flat(fixedPrior),"previous_targets_bone":flat(previousBone.joints),"current_targets_bone":flat(currentBone.joints),"targets":targets,"bone_source":report.boneSource,"bone_scale":currentBone.scale ?? 0,"bone_max_correction":report.boneMaxCorrection,"angle_corrections":report.angleCorrections,"knees_reflected":report.kneesReflected,"knee_clamp_degrees":report.kneeClampDegrees,"invalid":report.invalidJoints.sorted()])
        previousTargets=targets
    }
    outputs.append(["exercise":exercise,"frames":rows])
}
try JSONSerialization.data(withJSONObject:outputs,options:[.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
