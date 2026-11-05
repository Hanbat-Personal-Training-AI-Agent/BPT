import Foundation
import simd
func flat(_ p:[SIMD3<Double>])->[Double] { p.flatMap{[$0.x,$0.y,$0.z]} }
let null=NSNull()
var cases=[[String:Any]](), filter=BoneTargetContinuity()
let definitions:[([String:Double],Double?,String,String,Bool)]=[
 (["a":1,"b":1],0,"prior","A",true),(["a":3,"b":1],0.2,"session","A",true),
 (["a":3,"b":1],0.2,"session","A",true),(["a":1,"b":1],nil,"prior","A",true),
 (["a":0],0.3,"prior","A",true),(["a":1],0.4,"prior","A",false),
 (["a":1,"b":1],1,"prior","A",true),(["a":3,"b":1],3,"session","A",true),
 (["a":1,"b":1],0,"prior","B",true),(["c":1],0.04,"prior","B",true),
 (["a":1],0.05,"prior","",true),(["a":1],-1,"prior","B",true),
 (["a":1,"b":1],0.06,"prior","B",true),(["a":3,"b":1],0.10,"session","B",true)]
for (targets,t,source,epoch,valid) in definitions {
 let o=filter.update(targets:targets,sourceTime:t,source:source,profileEpoch:epoch,trackingValid:valid)
 cases.append(["targets":targets,"time":t.map{$0 as Any} ?? null,"source":source,"epoch":epoch,"tracking":valid,"original_shape":o.originalShape.map{$0 as Any} ?? null,"filtered_shape":o.filteredShape.map{$0 as Any} ?? null,"status":o.status,"alpha":o.alpha.map{$0 as Any} ?? null])
}
var groups=[[String:Any]]()
for exercise in ["squat","pushup","barbell_row"] {
 var full=Pose3DConstraints(),candidate=Pose3DConstraints(),f=BoneTargetContinuity()
 full.reflectFlippedKnee=exercise=="squat";candidate.reflectFlippedKnee=full.reflectFlippedKnee
 let base:[SIMD3<Double>]=[SIMD3(0,0,0),SIMD3(-0.1,0,0),SIMD3(-0.1,0.4,0.03),SIMD3(-0.1,0.8,0),SIMD3(0.1,0,0),SIMD3(0.1,0.4,0.03),SIMD3(0.1,0.8,0),SIMD3(0,-0.2,0),SIMD3(0,-0.4,0),SIMD3(0,-0.5,0),SIMD3(0,-0.6,0),SIMD3(0.2,-0.4,0),SIMD3(0.4,-0.25,0),SIMD3(0.6,-0.1,0),SIMD3(-0.2,-0.4,0),SIMD3(-0.4,-0.25,0),SIMD3(-0.6,-0.1,0)]
 var rows=[[String:Any]](),t=0.0
 for i in 0..<700 {
  t += i%3==0 ? 0.02 : 0.04
  if i==120 {t+=1.2}
  if i==350 {full=Pose3DConstraints();full.reflectFlippedKnee=exercise=="squat";candidate=full}
  var raw=base
  for j in 0..<17 {raw[j] += SIMD3(sin(Double(i)*0.07+Double(j))*0.02,cos(Double(i)*0.03+Double(j))*0.02,sin(Double(i)*0.04+Double(j))*0.05)}
  if i%71==0 {raw[15]=raw[14]+SIMD3(i%2==0 ? 0.002 : -0.002,0,0)}
  if i%97==0 {raw[8]=raw[7]+SIMD3(0.2,0.05,0)}
  if i%83==0 {raw[13]=raw[12]+(raw[11]-raw[12])*0.8+SIMD3(0.003,0,0)}
  if i==180 {f.reset();rows.append(["frame":i,"time":t,"tracking":false]);continue}
  let targets=full.sessionTargets() ?? full.priorLengths
  let source=full.sessionTargets()==nil ? "prior":"session"
  let o=f.update(targets:targets,sourceTime:t,source:source,profileEpoch:i<350 ? "A":"B")
  candidate.calibrationTargetsCm=o.filteredShape!
  let (b,br)=full.apply(raw), (c,cr)=candidate.apply(raw)
  rows.append(["raw":flat(raw),"frame":i,"time":t,"epoch":i<350 ? "A":"B","source":source,"targets":targets,"filtered_shape":o.filteredShape!,"status":o.status,"full":flat(b),"candidate":flat(c),"full_invalid":br.invalidJoints.sorted(),"candidate_invalid":cr.invalidJoints.sorted()])
 }
 groups.append(["exercise":exercise,"rows":rows])
}
let data=try JSONSerialization.data(withJSONObject:["filter_cases":cases,"groups":groups],options:[.sortedKeys])
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
