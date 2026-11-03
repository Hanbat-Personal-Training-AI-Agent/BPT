import XCTest
@testable import CalibrationEngineKit

final class MotionObserverAccountProfileTests: XCTestCase {
    private func payload() -> [String:Any] {
        ["schema":"bpt.account-motion-profile.v1","scope":"same_account_live_camera_assumption","jobId":"job-A",
         "engineeringWeight":["value":0.4,"source":"explicit per-profile test declaration","meaning":"explicit_engineering_weight_not_accuracy_probability"],
         "calibration":["schemaVersion":1,"stub":false,"bodyModel":"smpl_neutral_v1.1.0","smplBeta":Array(repeating:0.1,count:10),
           "boneLengthData":["unit":"cm","skeleton":"h36m17","pose":"rest","segments":["left_hip-left_knee":40.0,"left_knee-left_ankle":40.0,"right_hip-right_knee":40.0,"right_knee-right_ankle":40.0,"left_shoulder-left_elbow":30.0,"left_elbow-left_wrist":24.0,"hip_width":99.0],"appDefinitionDiffers":["left_shoulder-left_elbow"]],
           "quality":["perView":["front":["reprojectionErrorPx":4.2]]]]]
    }
    func testAcceptedLiveBindingRetainsDeclaredWeightAndExcludesDifferentDefinitions() throws {
        let gate=MotionObserverAccountProfileGate();XCTAssertTrue(gate.begin("A-session"))
        let ack=gate.accept(["binding":"A-session","profile":payload()],sourceSession:1,enabled:true,isVideo:false)
        XCTAssertEqual(ack["accepted"] as? Bool,true)
        let p=try XCTUnwrap(gate.snapshot(session:1))
        XCTAssertEqual(p.weight,0.4);XCTAssertEqual(p.ratios["1-2"],0.5)
        XCTAssertNil(p.ratios["11-12"]);XCTAssertEqual(p.ratios["12-13"],0.3)
        XCTAssertNil(p.ratios["0-4"],"display width must never become an anatomical bone")
    }
    func testStaleBindingsRecordedVideoAndSourceChangesCannotApplyProfile() throws {
        let gate=MotionObserverAccountProfileGate();gate.begin("A")
        XCTAssertEqual(gate.accept(["binding":"A","profile":payload()],sourceSession:1,enabled:true,isVideo:true)["accepted"] as? Bool,false)
        XCTAssertNil(gate.snapshot(session:1))
        gate.begin("B")
        XCTAssertEqual(gate.accept(["binding":"A","profile":payload()],sourceSession:2,enabled:true,isVideo:false)["reason"] as? String,"stale_binding")
        XCTAssertEqual(gate.accept(["binding":"B","profile":payload()],sourceSession:2,enabled:true,isVideo:false)["accepted"] as? Bool,true)
        XCTAssertNil(gate.snapshot(session:1));XCTAssertNotNil(gate.snapshot(session:2))
        gate.clear();XCTAssertNil(gate.snapshot(session:2))
        XCTAssertEqual(gate.accept(["binding":"B","profile":payload()],sourceSession:2,enabled:true,isVideo:false)["accepted"] as? Bool,false)
    }
    func testUnknownProvenanceQualityAndStrengthAreRejectedWithoutDefaults() {
        var noStub=payload();var c=noStub["calibration"] as! [String:Any];c.removeValue(forKey:"stub");noStub["calibration"]=c
        XCTAssertNil(MotionObserverAccountProfile.parse(noStub,binding:"A",sourceSession:1))
        var noQuality=payload();c=noQuality["calibration"] as! [String:Any];c["quality"]=[:];noQuality["calibration"]=c
        XCTAssertNil(MotionObserverAccountProfile.parse(noQuality,binding:"A",sourceSession:1))
        var noWeight=payload();noWeight["engineeringWeight"]=["source":"cannot infer weight from 4.2 pixels"]
        XCTAssertNil(MotionObserverAccountProfile.parse(noWeight,binding:"A",sourceSession:1))
    }
    func testProfileAffectsOnlyObserverAndTravelsWithOwnL5Entry() throws {
        let fixture=try MotionAGFormerLiveTests().fixture()
        let profile=try XCTUnwrap(MotionObserverAccountProfile.parse(payload(),binding:"A",sourceSession:1))
        var baseline=MotionAGFormerLive<Int>(predict:MotionAGFormerLiveTests.fakePredict)
        var live=MotionAGFormerLive<Int>(predict:MotionAGFormerLiveTests.fakePredict)
        live.motionObserver=ExerciseMotionObserver(configuration:.init(exercise:"pushup",variant:.H,profile:nil,fixedCameraAssertion:false))
        var seen=0
        for (i,values) in fixture.coco17.enumerated() {
            let kp=values.map { PoseKeypoint(x:$0[0],y:$0[1],confidence:$0[2]) }
            let source=ExerciseMotionObserver.Source(session:1,frame:i,sourceIndex:i,pts:Double(i)/30,timeValue:Int64(i*100),timeScale:3000,rotation:0,width:fixture.image_size[0],height:fixture.image_size[1],isVideo:false,profileBinding:"A")
            let a=try baseline.push(frameIndex:i,coco17:kp,imageWidth:fixture.image_size[0],imageHeight:fixture.image_size[1],payload:i)
            let b=try live.push(frameIndex:i,coco17:kp,imageWidth:fixture.image_size[0],imageHeight:fixture.image_size[1],observerSource:source,observerProfile:profile,payload:i)
            for ((_,fa),(_,fb)) in zip(a,b) {
                XCTAssertEqual(fa.raw,fb.raw);XCTAssertEqual(fa.pose3D,fb.pose3D);XCTAssertEqual(fa.invalidJoints,fb.invalidJoints);XCTAssertEqual(fa.state,fb.state)
                if let observed=fb.motionObservation {seen+=1;XCTAssertEqual(observed.details["personal_profile_applied"] as? Bool,true);XCTAssertEqual(observed.source.profileBinding,"A")}
            }
        }
        XCTAssertGreaterThan(seen,0)
    }
    func testFractionalVersionBooleanVersionAndNonfiniteQualityStayRejected() throws {
        for bad in [true, 1.5, 1.9] as [Any] {
            var p=payload();var c=p["calibration"] as! [String:Any];c["schemaVersion"]=bad;p["calibration"]=c
            XCTAssertNil(MotionObserverAccountProfile.parse(p,binding:"A",sourceSession:1))
        }
        var p=payload();var c=p["calibration"] as! [String:Any];c["stub"]=0;p["calibration"]=c
        XCTAssertNil(MotionObserverAccountProfile.parse(p,binding:"A",sourceSession:1))
        c["stub"]=false;c["quality"]=["perView":["front":["reprojectionErrorPx":Double.nan]]];p["calibration"]=c
        XCTAssertNil(MotionObserverAccountProfile.parse(p,binding:"A",sourceSession:1))
        c["quality"]=["ignored":Double.nan,"perView":["front":["reprojectionErrorPx":4.2]]];p["calibration"]=c
        let parsed=try XCTUnwrap(MotionObserverAccountProfile.parse(p,binding:"A",sourceSession:1))
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:parsed.qualityEvidence))
        XCTAssertNil(parsed.qualityEvidence["ignored"])
    }
    func testBoundProfileIsNotReportedAppliedForVariantA() throws {
        let p=try XCTUnwrap(MotionObserverAccountProfile.parse(payload(),binding:"A",sourceSession:1))
        let f=try MotionAGFormerLiveTests().fixture();let kp=f.coco17[0].map {PoseKeypoint(x:$0[0],y:$0[1],confidence:$0[2])}
        let screen=try PoseCoordinateTransforms.coco17ToH36M17(kp).map {SIMD3($0.x/480,$0.y/480,$0.confidence)}
        let raw=screen.map {SIMD3($0.x,$0.y,0)}
        let source=ExerciseMotionObserver.Source(session:1,frame:0,sourceIndex:0,pts:0,timeValue:0,timeScale:30,rotation:0,width:640,height:480,isVideo:false,profileBinding:"A")
        var observer=ExerciseMotionObserver(configuration:.init(exercise:"pushup",variant:.A,profile:nil,fixedCameraAssertion:false))
        let output=observer.update(raw:raw,screen2D:screen,modelToImageScale:1,source:source,flush:false,accountProfile:p)
        XCTAssertEqual(output.details["personal_profile_bound"] as? Bool,true)
        XCTAssertEqual(output.details["personal_profile_applied"] as? Bool,false)
        XCTAssertEqual(output.details["personal_profile_job_id"] as? String,"job-A")
        XCTAssertNotNil(output.details["personal_profile_quality_evidence"])
    }

}
