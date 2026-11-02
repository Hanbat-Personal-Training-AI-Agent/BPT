import Foundation
import simd
let null=NSNull()
func finite(_ x:Double?)->Any {guard let x,x.isFinite else{return null};return x}
func pose(_ v:Any?)->[SIMD3<Double>]? {
 guard let v=v as? [Any],v.count==51 else{return nil}
 return stride(from:0,to:51,by:3).map{ i in SIMD3((v[i] as? Double) ?? .nan,(v[i+1] as? Double) ?? .nan,(v[i+2] as? Double) ?? .nan)}
}
func geometry(_ row:[String:Any],raw:[SIMD3<Double>]?,corrected:[SIMD3<Double>]?,confidence:[Double]?,invalid:Set<Int>,ids:[Int],fn:([SIMD3<Double>])->Double?)->[String:Any] {
 let a=raw.flatMap(fn),b=corrected.flatMap(fn);var reasons=[String]()
 if !["ok","partial_3d"].contains(row["assessment_state"] as? String ?? "") {reasons.append("unusable_3d")}
 if !invalid.isDisjoint(with:ids) {reasons.append("invalid_joint")}
 if let c=confidence,c.count==17 {if ids.contains(where:{!c[$0].isFinite || c[$0]<0.5}) {reasons.append("low_joint_support")}} else {reasons.append("missing_joint_support")}
 if a == nil || a?.isFinite != true {reasons.append("missing_raw_geometry")}
 if b == nil || b?.isFinite != true {reasons.append("missing_geometry")}
 return ["rawValue":finite(a),"value":finite(b),"reasons":reasons,"available":reasons.isEmpty,"requiredJoints":ids,"scope":"camera_reference_proxy","qualifiers":["source_gravity_not_synchronized","not_anatomical_or_lumbar_approval","no_approved_ratio_correction_bound"]]
}
if CommandLine.arguments[1]=="--self-test" {
 var j=[SIMD3<Double>](repeating:.zero,count:17);j[8]=[0,-1,0];j[11]=[0.5,-1,0];j[14]=[-0.5,-1,0]
 j[12]=j[11]+[sin(.pi/3),cos(.pi/3),0];j[15]=j[14]+[-sin(.pi/3),cos(.pi/3),0]
 var engine=ExperimentalCoaching();let out=engine.update(.init(time:0,exercise:"pushup",phase:"bottom",state:"ok",raw:j,corrected:j,confidence:Array(repeating:0.9,count:17),invalid:[],up:nil))
 precondition(abs(out.metrics["leftUpperArmDeg"]!.value!-60)<1e-8)
 precondition(out.metrics["trunkInclineDeg"]!.value==nil && out.candidates.allSatisfy{$0.assessment=="withheld"})
 precondition(SourceGeometry.unwrapDegrees([179,-179])==[179,181])
 j[3]=[0,0,1];j[6]=[0,0,1];precondition(SourceGeometry.signedHipDeviation3D(j) != nil)
 print("source formulas/profile-nil/gravity/unwrap synthetic PASS")
} else {
 let groups=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
 var results=[[String:Any]]()
 for group in groups {
  var engine=ExperimentalCoaching(),rows=[[String:Any]]()
  for row in group["frames"] as! [[String:Any]] {
   let raw=pose(row["raw_3d"]),corrected=pose(row["assessment_3d"]),confidence=row["confidence_h36m"] as? [Double],invalid=Set(row["invalid"] as! [Int])
   let exercise=group["exercise"] as! String
   let frame=ExperimentalCoaching.Frame(time:row["source_pts"] as! Double,exercise:exercise,phase:row["phase"] as? String,state:row["assessment_state"] as! String,raw:raw,corrected:corrected,confidence:confidence,invalid:invalid,up:nil)
   let output=engine.update(frame,profile:nil)
   var metrics=(try JSONSerialization.jsonObject(with:JSONEncoder().encode(output)) as! [String:Any])["metrics"] as! [String:Any]
   metrics["cameraTorsoSignedDeg"]=geometry(row,raw:raw,corrected:corrected,confidence:confidence,invalid:invalid,ids:[0,1,4,8]){SourceGeometry.signedTorsoAngle3D($0)}
   metrics["cameraHipLineDeviationRatio"]=geometry(row,raw:raw,corrected:corrected,confidence:confidence,invalid:invalid,ids:[0,8,3,6]){SourceGeometry.signedHipDeviation3D($0)}
   var samples=[String:Any]()
   if let a=row["assessment_2d"] as? [Double],a.count==51 {
    for (side,shoulder,hip) in [("left",5,11),("right",6,12)] {
     let values=[a[3*shoulder],a[3*shoulder+1],a[3*hip],a[3*hip+1]],supported=values.allSatisfy{$0.isFinite} && a[3*shoulder+2]>=SourceGeometry.min2DConfidence && a[3*hip+2]>=SourceGeometry.min2DConfidence
     samples[side]=["hipY":supported ? finite(a[3*hip+1]):null,"shoulderY":supported ? finite(a[3*shoulder+1]):null,"available":supported,"reasons":supported ? []:["low_or_missing_2d_support"],"scope":"image_plane_pixels_not_3d_height"]
    }
   }
   let nativeOutput=try JSONSerialization.jsonObject(with:JSONEncoder().encode(output)) as! [String:Any]
   rows.append(["frame":row["frame"]!,"metrics":metrics,"candidates":nativeOutput["candidates"]!,"image_samples":samples])
  }
  results.append(["exercise":group["exercise"]!,"rows":rows])
 }
 try JSONSerialization.data(withJSONObject:results,options:[.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
}
