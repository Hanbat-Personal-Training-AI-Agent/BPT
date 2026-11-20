import Foundation
import simd
let null=NSNull()
func safe(_ x:Double?)->Any { guard let x,x.isFinite else{return null};return x }
func pointJSON(_ p:[SIMD3<Double>])->[[Any]] {p.map{[safe($0.x),safe($0.y),safe($0.z)]}}
func segmentJSON(_ r:[String:BoneLengthConstraint.SegmentReport])->[String:Any] {
 r.mapValues{v in ["observed":safe(v.observed),"output":safe(v.output),"target_cm":safe(v.targetCm),"constrained":v.constrained,"degenerate":v.degenerate] as [String:Any]}
}
func encode(_ r:BoneCorrectionReliability.Result)->[String:Any] {
 ["segments":r.segments.map{e in ["name":e.name,"parent":e.parent,"child":e.child,"observed":safe(e.observed),"output":safe(e.output),"absolute_length_correction":safe(e.absoluteLengthCorrection),"expansion":safe(e.expansion),"status":e.status,"reasons":e.reasons] as [String:Any]},"existing_invalid":r.existingInvalid.sorted(),"additional_invalid":r.additionalInvalid.sorted(),"invalid":r.invalid.sorted(),"global_reasons":r.globalReasons]
}
func write(_ object:Any,_ path:String) throws {try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]).write(to:URL(fileURLWithPath:path))}
if CommandLine.arguments[1]=="--synthetic" {
 let base:[SIMD3<Double>]=[SIMD3(0,0,0),SIMD3(-0.25,0,0),SIMD3(-0.25,1,0),SIMD3(-0.25,2,0),SIMD3(0.25,0,0),SIMD3(0.25,1,0),SIMD3(0.25,2,0),SIMD3(0,-0.5,0),SIMD3(0,-1,0),SIMD3(0,-1.5,0),SIMD3(0,-2,0),SIMD3(0.5,-1,0),SIMD3(1.5,-1,0),SIMD3(2.5,-1,0),SIMD3(-0.5,-1,0),SIMD3(-1.5,-1,0),SIMD3(-2.5,-1,0)]
 let targets=Dictionary(uniqueKeysWithValues:BoneLengthConstraint.defaultSegments.map{($0,1.0)})
 var cases=[[String:Any]]()
 for name in ["normal","boundary4","collapsed_right","collapsed_left","direction_flip","zero","nonfinite_elbow","nonfinite_head","missing_target","invalid_target","missing_scale","invalid_scale","missing_report","unprojected","inconsistent_report","existing_mask","out_of_bounds_mask","malformed"] {
  var raw=base,existing:Set<Int>=[]
  if ["collapsed_right","direction_flip","boundary4"].contains(name) {let sign=name=="direction_flip" ? 1.0 : -1.0;raw[15]=raw[14]+SIMD3(sign*(name=="boundary4" ? 0.25:0.125),0,0);raw[16]=raw[15]+SIMD3(sign,0,0)}
  if name=="collapsed_left" {raw[12]=raw[11]+SIMD3(0.125,0,0);raw[13]=raw[12]+SIMD3(1,0,0)}
  if name=="zero" {raw[15]=raw[14]}
  // Native solver is not invoked with malformed/nonfinite coordinates; its valid report is then invalidated as external evidence.
  let bone=BoneLengthConstraint.apply(raw,targetsCm:targets);var reports=bone.segments,scale=bone.scale
  if name=="nonfinite_elbow" {raw[15].x=Double.nan}
  if name=="nonfinite_head" {raw[10].x=Double.nan}
  let edge="right_shoulder-right_elbow"
  if name=="missing_target" {reports[edge]!.targetCm=nil}
  if name=="invalid_target" {reports[edge]!.targetCm = -1}
  if name=="missing_scale" {scale=nil}
  if name=="invalid_scale" {scale = -1}
  if name=="missing_report" {reports.removeValue(forKey:edge)}
  if name=="unprojected" {reports[edge]!.constrained=false}
  if name=="inconsistent_report" {reports[edge]!.observed+=0.1}
  if name=="existing_mask" {existing=[5,10]}
  if name=="out_of_bounds_mask" {existing=[5,99]}
  if name=="malformed" {raw.removeLast()}
  let before=pointJSON(raw)
  let result=BoneCorrectionReliability.evaluate(raw:raw,segments:reports,scale:scale,existingInvalid:existing)
  precondition(NSArray(array:before).isEqual(to:pointJSON(raw)))
  cases.append(["case":name,"raw":pointJSON(raw),"segments":segmentJSON(reports),"scale":safe(scale),"existing_invalid":existing.sorted(),"result":encode(result)])
 }
 try write(cases,CommandLine.arguments[2])
} else {
 let groups=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Any]]
 var output=[[String:Any]](),maxError=0.0,coordinateCount=0,nonzeroComponents=0
 for g in groups {
  let exercise=g["exercise"] as! String;var full=Pose3DConstraints();full.reflectFlippedKnee=exercise=="squat"
  var rows=[[String:Any]]()
  for input in g["frames"] as! [[String:Any]] {
   let a=input["raw"] as! [Double],raw=stride(from:0,to:51,by:3).map{SIMD3(a[$0],a[$0+1],a[$0+2])}
   let targets=full.sessionTargets() ?? full.priorLengths,bone=BoneLengthConstraint.apply(raw,targetsCm:targets)
   let (fixed,report)=full.apply(raw),expected=input["full"] as! [Double],existing=Set(input["invalid"] as! [Int])
   let flat=fixed.flatMap{[$0.x,$0.y,$0.z]};let differences=zip(flat,expected).map{abs($0-$1)};let error=differences.max()!
   nonzeroComponents+=differences.filter{$0 != 0}.count
   if !error.isFinite || error > 1e-12 || report.invalidJoints != existing {
    try write(["gate_failed":true,"exercise":exercise,"frame":input["frame"]!,"maximum_coordinate_error":error,"expected_invalid":existing.sorted(),"actual_invalid":report.invalidJoints.sorted()],CommandLine.arguments[2]+".failure.json")
    exit(3)
   }
   maxError=max(maxError,error);coordinateCount+=51
   let evidence=BoneCorrectionReliability.evaluate(raw:raw,segments:bone.segments,scale:bone.scale,existingInvalid:existing)
   precondition(raw.flatMap{[$0.x,$0.y,$0.z]}==a,"raw input mutated")
   rows.append(["frame":input["frame"]!,"segments_input":segmentJSON(bone.segments),"scale":safe(bone.scale),"result":encode(evidence)])
  }
  output.append(["exercise":exercise,"frames":rows])
 }
 try write(["baseline_max_coordinate_error":maxError,"baseline_coordinate_components":coordinateCount,"baseline_nonzero_coordinate_components":nonzeroComponents,"coordinate_tolerance":1e-12,"existing_masks_exact":true,"raw_arrays_unchanged":true,"groups":output],CommandLine.arguments[2])
}
