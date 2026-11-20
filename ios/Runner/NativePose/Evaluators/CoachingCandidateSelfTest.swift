import Foundation
import simd

/// Explicit opt-in synthetic geometry witness. Never reads or replaces camera/model coordinates.
struct CoachingCandidateSelfTest {
    private var engine=CoachingCandidateEngine()
    private var presenter=CoachingCandidateProposal()
    private let captureID="synthetic-fixture:"+UUID().uuidString
    mutating func run(stage:String,declaredAt:String) throws -> [String:Any]? {
        let index=stage=="positive" ? 0:1
        var joints=[SIMD3<Double>](repeating:.zero,count:17)
        joints[0]=SIMD3(0,0.5,1);joints[8]=SIMD3(0,0,0)
        joints[1]=SIMD3(-0.2,0.5,1);joints[4]=SIMD3(0.2,0.5,1)
        joints[2]=SIMD3(-0.2,0.1,1.5);joints[5]=SIMD3(0.2,0.1,1.5)
        joints[3]=SIMD3(-0.2,0,2);joints[6]=SIMD3(0.2,0,2)
        joints[11]=SIMD3(0.3,0,0);joints[12]=SIMD3(0.8,0.1,0.3);joints[13]=SIMD3(0.9,0.3,0.5)
        joints[14]=SIMD3(-0.3,0,0);joints[15]=SIMD3(-0.8,0.1,0.3);joints[16]=SIMD3(-0.9,0.3,0.5)
        let frame=CoachingCandidateEngine.Frame(source:["epoch":0,"frame":index,"source_index":index,"source_pts":Double(index)*0.1,"source_time_value":index,"source_time_scale":10,"time_basis":"sample_pts_seconds"],context:["exercise":"pushup","phase":"descending","side":"left","side_view":NSNull(),"source_kind":"synthetic_fixture","flush_tail":false,"rotation":0,"size":[640,480],"source_mirrored":false],raw3D:joints,assessment3D:joints,raw2D:nil,confidence:[Double](repeating:1,count:17),invalid:index==0 ? []:[3],state:"ok",captureID:captureID)
        let config=try CoachingCandidateEngine.Configuration(experimentID:"explicit-native-synthetic-proposal-witness",source:"fully synthetic geometry for channel/banner/occlusion testing; not current video or accuracy evidence",experimentDeclaredAt:declaredAt,variant:"floor",overrides:["support.maximumHipRatioCorrection":0.05],provenance:["support.maximumHipRatioCorrection":"synthetic geometry fixture engineering tolerance"])
        let result=try engine.update(frame,configuration:config)
        if stage=="positive" {return presenter.next(result)}
        return presenter.expireIfNeeded(result)
    }
}
