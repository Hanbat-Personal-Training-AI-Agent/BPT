import Foundation
import simd
func close(_ a:Double,_ b:Double) { precondition(abs(a-b)<1e-12,"\(a) != \(b)") }
let a=["a":1.0,"b":1.0],b=["a":3.0,"b":1.0]
var filter=BoneTargetContinuity()
let first=filter.update(targets:a,sourceTime:0,source:"prior",profileEpoch:"A")
close(first.filteredShape!["a"]!,0.5)
let step=filter.update(targets:b,sourceTime:0.2,source:"session",profileEpoch:"A")
precondition(step.status=="filtered");close(step.alpha!,0.5);close(step.filteredShape!["a"]!,0.625)
precondition(step.originalTargets==b && step.source=="session")
let profile=filter.update(targets:b,sourceTime:0,source:"session",profileEpoch:"B")
precondition(profile.status=="reset_profile_epoch");close(profile.filteredShape!["a"]!,0.75)
precondition(filter.update(targets:a,sourceTime:0,source:"prior",profileEpoch:"B").status=="unsupported_nonmonotonic_time")
precondition(filter.update(targets:a,sourceTime:0.1,source:"prior",profileEpoch:"B").status=="initialized")
precondition(filter.update(targets:b,sourceTime:2,source:"session",profileEpoch:"B").status=="reset_long_gap")
precondition(filter.update(targets:b,sourceTime:nil,source:"session",profileEpoch:"B").filteredShape==nil)
for bad in [["a":0.0],["a":Double.nan],["a":Double.infinity],[String:Double]()] {
 precondition(filter.update(targets:bad,sourceTime:3,source:"session",profileEpoch:"B").status=="unsupported_target")
}
precondition(filter.update(targets:a,sourceTime:3,source:"prior",profileEpoch:"B",trackingValid:false).status=="unsupported_tracking")
precondition(filter.update(targets:a,sourceTime:4,source:"prior",profileEpoch:"B").status=="initialized")
precondition(filter.update(targets:["c":1],sourceTime:4.1,source:"prior",profileEpoch:"B").status=="reset_target_keys")
precondition(filter.update(targets:a,sourceTime:Double.infinity,source:"s",profileEpoch:"B").filteredShape==nil)
precondition(filter.update(targets:a,sourceTime:-1,source:"s",profileEpoch:"B").filteredShape==nil)
precondition(filter.update(targets:a,sourceTime:4,source:"s",profileEpoch:"").filteredShape==nil)
filter.reset();precondition(filter.update(targets:a,sourceTime:0,source:"prior",profileEpoch:"B").status=="initialized")
var x=BoneTargetContinuity(),y=BoneTargetContinuity()
_ = x.update(targets:a,sourceTime:0,source:"p",profileEpoch:"A");_ = y.update(targets:a,sourceTime:0,source:"p",profileEpoch:"A")
_ = x.update(targets:b,sourceTime:0.1,source:"s",profileEpoch:"A")
let xx=x.update(targets:b,sourceTime:0.2,source:"s",profileEpoch:"A")
let yy=y.update(targets:b.mapValues{$0*100},sourceTime:0.2,source:"s",profileEpoch:"A")
close(xx.filteredShape!["a"]!,yy.filteredShape!["a"]!) // actual dt and shape-scale invariance
// Isolated direction reversal: filtered targets cannot remember a previous joint direction.
var raw=(0..<17).map { SIMD3<Double>(Double($0),Double($0%3),0) }
raw[11]=SIMD3(0,0,0);raw[12]=SIMD3(1,0,0);raw[13]=SIMD3(2,0,0)
let original=raw
let targets=["left_shoulder-left_elbow":1.0,"left_elbow-left_wrist":1.0]
var directionFilter=BoneTargetContinuity()
let shape1=directionFilter.update(targets:targets,sourceTime:0,source:"prior",profileEpoch:"direction").filteredShape!
let out1=BoneLengthConstraint.apply(raw,targetsCm:shape1).joints
raw[12]=SIMD3(-1,0,0);raw[13]=SIMD3(-2,0,0)
let shape2=directionFilter.update(targets:targets,sourceTime:0.2,source:"session",profileEpoch:"direction").filteredShape!
let out2=BoneLengthConstraint.apply(raw,targetsCm:shape2).joints
precondition(out1[12].x-out1[11].x>0 && out2[12].x-out2[11].x<0)
precondition(original[12].x==1 && raw[12].x == -1) // no mutation of caller's raw values
print("BoneTargetContinuity synthetic contract PASS (time/shape/reset/ownership/direction)")
