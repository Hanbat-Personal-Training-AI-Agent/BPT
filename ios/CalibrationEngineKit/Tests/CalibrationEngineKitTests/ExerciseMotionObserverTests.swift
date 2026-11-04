import XCTest
@testable import CalibrationEngineKit

final class ExerciseMotionObserverTests: XCTestCase {
    private func source(_ i: Int, session: Int = 1, pts: Double? = nil) -> ExerciseMotionObserver.Source {
        .init(session: session, frame: i, sourceIndex: i, pts: pts ?? Double(i) / 30,
              timeValue: Int64(i * 100), timeScale: 3000, rotation: 0,
              width: 640, height: 480, isVideo: true)
    }
    private func config(_ variant: ExerciseMotionVariant, exercise: String = "pushup") -> ExerciseMotionObserver.Configuration {
        .init(exercise: exercise, variant: variant, profile: nil, fixedCameraAssertion: false)
    }
    private func assertPose(_ a: [SIMD3<Double>]?, _ b: [SIMD3<Double>]?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a?.count, b?.count, file: file, line: line)
        for (p, q) in zip(a ?? [], b ?? []) { for j in 0..<3 { XCTAssertEqual(p[j].bitPattern, q[j].bitPattern, file: file, line: line) } }
    }
    func testDefaultOffAndUnknownCameraCannotBecomeFixedContact() throws {
        XCTAssertNil(try ExerciseMotionObserver.Configuration.parse(environment: [:], exercise: "pushup", isVideo: true))
        XCTAssertNil(try ExerciseMotionObserver.Configuration.parse(environment: ["BPT_MOTION_OBSERVER": "OFF"], exercise: "pushup", isVideo: true))
        let c = try XCTUnwrap(ExerciseMotionObserver.Configuration.parse(environment: ["BPT_MOTION_OBSERVER": "H", "BPT_MOTION_OBSERVER_FIXED_CAMERA": "1"], exercise: "pushup", isVideo: false))
        XCTAssertFalse(c.fixedCameraAssertion)
        XCTAssertNil(c.profile)
    }
    func testSourceSessionRejectsStoppedAndSupersededGenerations() {
        let s = ExerciseMotionObserver.SourceSession()
        XCTAssertNil(s.snapshot()); s.begin()
        let old = s.snapshot()
        XCTAssertTrue(s.accepts(old)); s.end(); XCTAssertFalse(s.accepts(old))
        let stoppedRevision = s.revision()
        s.begin(); XCTAssertFalse(s.accepts(old)); XCTAssertTrue(s.accepts(s.snapshot()))
        XCTAssertNotEqual(s.revision(), stoppedRevision)
    }
    func testEveryVariantKeepsCurrentRawConstraintsAssessmentAndWarningsIdentical() throws {
        let fixture = try MotionAGFormerLiveTests().fixture()
        for exercise in [FormExercise.pushUp, .squat, .barbellRow] {
            for variant in ExerciseMotionVariant.allCases {
                var baseline = MotionAGFormerLive<Int>(predict: MotionAGFormerLiveTests.fakePredict)
                var observed = MotionAGFormerLive<Int>(predict: MotionAGFormerLiveTests.fakePredict)
                observed.motionObserver = ExerciseMotionObserver(configuration: config(variant, exercise: exercise.rawValue))
                let oldTracker = FormWarningTracker(exercise: exercise)
                let newTracker = FormWarningTracker(exercise: exercise)
                oldTracker.beginRep(); newTracker.beginRep()
                var compared = 0
                for (i, values) in fixture.coco17.enumerated() {
                    let kp = values.map { PoseKeypoint(x: $0[0], y: $0[1], confidence: $0[2]) }
                    let a = try baseline.push(frameIndex: i, coco17: kp, imageWidth: fixture.image_size[0], imageHeight: fixture.image_size[1], payload: i)
                    let stamp = ExerciseMotionObserver.Source(session: 1, frame: i, sourceIndex: i, pts: Double(i)/30,
                        timeValue: Int64(i*100), timeScale: 3000, rotation: 0, width: fixture.image_size[0], height: fixture.image_size[1], isVideo: true)
                    let b = try observed.push(frameIndex: i, coco17: kp, imageWidth: fixture.image_size[0], imageHeight: fixture.image_size[1], observerSource: stamp, payload: i)
                    XCTAssertEqual(a.count, b.count)
                    for ((pa, fa), (pb, fb)) in zip(a, b) {
                        XCTAssertEqual(pa, pb); XCTAssertEqual(fa.state, fb.state)
                        assertPose(fa.raw, fb.raw); assertPose(fa.pose3D, fb.pose3D); assertPose(fa.masked3D, fb.masked3D)
                        XCTAssertEqual(fa.invalidJoints, fb.invalidJoints)
                        XCTAssertEqual(fa.constraints?.boneMaxCorrection, fb.constraints?.boneMaxCorrection)
                        oldTracker.observe(frameIndex: pa, coco17: fixture.coco17[pa].map { PoseKeypoint(x:$0[0],y:$0[1],confidence:$0[2]) }, pose3D: fa.masked3D, pose3DState: fa.state, phase: "unknown")
                        newTracker.observe(frameIndex: pb, coco17: fixture.coco17[pb].map { PoseKeypoint(x:$0[0],y:$0[1],confidence:$0[2]) }, pose3D: fb.masked3D, pose3DState: fb.state, phase: "unknown")
                        oldTracker.recordCurrentFrame(); newTracker.recordCurrentFrame()
                        if let output = fb.motionObservation {
                            compared += 1
                            XCTAssertEqual(output.source.frame, pb)
                            XCTAssertEqual(output.source.timeValue, Int64(pb*100))
                            XCTAssertEqual(output.source.pts!, Double(pb)/30, accuracy: 1e-12)
                            assertPose(output.raw, fb.raw)
                            XCTAssertEqual(output.dictionary["adopted_for_feedback"] as? Bool, false)
                            XCTAssertLessThan(try JSONSerialization.data(withJSONObject: output.dictionary).count, 24_576)
                        }
                    }
                }
                XCTAssertGreaterThan(compared, 0)
                let af = try baseline.flush().map(\.1), bf = try observed.flush().map(\.1)
                XCTAssertEqual(af.count, bf.count)
                for (a,b) in zip(af,bf) {
                    assertPose(a.raw,b.raw);assertPose(a.pose3D,b.pose3D);assertPose(a.masked3D,b.masked3D)
                    XCTAssertEqual(a.state,b.state);XCTAssertEqual(a.invalidJoints,b.invalidJoints)
                    XCTAssertTrue(b.diagnosticFlushed)
                    if let o=b.motionObservation { XCTAssertNil(o.candidate);XCTAssertEqual(o.reasons,["flush_tail_not_fresh_observation"]) }
                }
                let ar=oldTracker.finishRep(repIndex:1),br=newTracker.finishRep(repIndex:1)
                XCTAssertEqual(try JSONSerialization.data(withJSONObject:ar.dictionary,options:.sortedKeys),
                               try JSONSerialization.data(withJSONObject:br.dictionary,options:.sortedKeys))
            }
        }
    }
    func testMissingClockAndFlushWithholdInsteadOfGuessingAndResetHistory() throws {
        let fixture = try MotionAGFormerLiveTests().fixture()
        let kp = fixture.coco17[0].map { PoseKeypoint(x:$0[0],y:$0[1],confidence:$0[2]) }
        let screen = try PoseCoordinateTransforms.coco17ToH36M17(kp).map { SIMD3($0.x/480,$0.y/480,$0.confidence) }
        let raw = screen.map { SIMD3($0.x,$0.y,0) }
        var observer = ExerciseMotionObserver(configuration: config(.G))
        let missing = ExerciseMotionObserver.Source(session:1,frame:0,sourceIndex:0,pts:nil,timeValue:nil,timeScale:nil,rotation:0,width:640,height:480,isVideo:true)
        XCTAssertNil(observer.update(raw:raw,screen2D:screen,modelToImageScale:1,source:missing,flush:false).candidate)
        XCTAssertNil(observer.update(raw:raw,screen2D:screen,modelToImageScale:1,source:source(1),flush:true).candidate)
        let reset=observer.update(raw:raw,screen2D:screen,modelToImageScale:1,source:source(2,session:2),flush:false)
        var fresh=ExerciseMotionObserver(configuration:config(.G))
        let expected=fresh.update(raw:raw,screen2D:screen,modelToImageScale:1,source:source(2,session:2),flush:false)
        assertPose(reset.candidate,expected.candidate)
        XCTAssertEqual(reset.details["phase_source"] as? String,"internal_heuristic_not_observed")
        XCTAssertEqual(reset.details["contact_evidence"] as? String,"unknown")
    }
    func testRequestedPersonalProfileIsWithheldWithoutReadingUnboundFile() throws {
        let c = try XCTUnwrap(ExerciseMotionObserver.Configuration.parse(environment: ["BPT_MOTION_OBSERVER":"H", "BPT_MOTION_OBSERVER_PROFILE":"/must-not-read-an-unbound-profile"], exercise:"pushup", isVideo:true))
        XCTAssertNil(c.profile); XCTAssertTrue(c.profileRequested)
    }
    func testDelayedOutputUsesItsOwnTwoDScaleAndRationalTime() throws {
        let f = try MotionAGFormerLiveTests().fixture()
        var normalizer = MotionAGFormerInputNormalizer()
        var expectedInputs: [(screen: [SIMD3<Double>], scale: Double, source: ExerciseMotionObserver.Source)] = []
        var direct = ExerciseMotionObserver(configuration:config(.H))
        var live = MotionAGFormerLive<Int>(lookahead:5,predict:MotionAGFormerLiveTests.fakePredict)
        live.motionObserver = ExerciseMotionObserver(configuration:config(.H))
        var compared=0
        for (i,values) in f.coco17.enumerated() {
            let kp=values.map { PoseKeypoint(x:$0[0],y:$0[1],confidence:$0[2]) }
            let h=try PoseCoordinateTransforms.coco17ToH36M17(kp)
            _ = normalizer.normalize(h,imageWidth:f.image_size[0],imageHeight:f.image_size[1])
            let stamp=ExerciseMotionObserver.Source(session:1,frame:i,sourceIndex:i,pts:Double(i)/30,timeValue:Int64(i*100),timeScale:3000,rotation:0,width:f.image_size[0],height:f.image_size[1],isVideo:true)
            expectedInputs.append((h.map { SIMD3($0.x/Double(f.image_size[1]),$0.y/Double(f.image_size[1]),$0.confidence) },(normalizer.lastCrop?.side ?? 2)/(2*Double(f.image_size[1])),stamp))
            let out=try live.push(frameIndex:i,coco17:kp,imageWidth:f.image_size[0],imageHeight:f.image_size[1],observerSource:stamp,payload:i)
            for (index,frame) in out {
                guard let actual=frame.motionObservation,let raw=frame.raw else { continue }
                XCTAssertLessThan(index,i)
                let expected=expectedInputs[index]
                let want=direct.update(raw:raw,screen2D:expected.screen,modelToImageScale:expected.scale,source:expected.source,flush:false)
                assertPose(actual.candidate,want.candidate)
                XCTAssertEqual(actual.source.timeValue,expected.source.timeValue)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared,0)
    }
    func testMismatchedEntryStampIsRejectedAndStoppedRecheckCannotReactivate() throws {
        let f=try MotionAGFormerLiveTests().fixture()
        let kp=f.coco17[0].map { PoseKeypoint(x:$0[0],y:$0[1],confidence:$0[2]) }
        var live=MotionAGFormerLive<Int>(predict:MotionAGFormerLiveTests.fakePredict)
        live.motionObserver=ExerciseMotionObserver(configuration:config(.G))
        for i in 0..<40 {
            let wrong=ExerciseMotionObserver.Source(session:1,frame:i+1,sourceIndex:i,pts:Double(i)/30,timeValue:Int64(i*100),timeScale:3000,rotation:0,width:f.image_size[0],height:f.image_size[1],isVideo:true)
            let out=try live.push(frameIndex:i,coco17:kp,imageWidth:f.image_size[0],imageHeight:f.image_size[1],observerSource:wrong,payload:i)
            XCTAssertTrue(out.allSatisfy { $0.1.motionObservation == nil })
        }
        let session=ExerciseMotionObserver.SourceSession();session.begin();let old=session.snapshot()
        session.end();XCTAssertNil(session.rotateIfCurrent(old));XCTAssertNil(session.snapshot())
        session.begin();let current=session.snapshot();XCTAssertNil(session.rotateIfCurrent(old));XCTAssertEqual(session.snapshot(),current)
    }

    func testMissingSourceResetsInDelayedEmissionOrder() throws {
        let f=try MotionAGFormerLiveTests().fixture()
        var live=MotionAGFormerLive<Int>(lookahead:5,predict:MotionAGFormerLiveTests.fakePredict)
        live.motionObserver=ExerciseMotionObserver(configuration:config(.G))
        var normalizer=MotionAGFormerInputNormalizer()
        var inputs:[Int:([SIMD3<Double>],Double,ExerciseMotionObserver.Source)]=[:]
        var checked=false
        for i in 0..<40 {
            let values=f.coco17[min(i,f.coco17.count-1)]
            let kp=values.map { PoseKeypoint(x:$0[0],y:$0[1],confidence:$0[2]) }
            let h=try PoseCoordinateTransforms.coco17ToH36M17(kp)
            _=normalizer.normalize(h,imageWidth:f.image_size[0],imageHeight:f.image_size[1])
            let src=ExerciseMotionObserver.Source(session:1,frame:i,sourceIndex:i,pts:Double(i)/30,timeValue:Int64(i*100),timeScale:3000,rotation:0,width:f.image_size[0],height:f.image_size[1],isVideo:true)
            inputs[i]=(h.map { SIMD3($0.x/Double(f.image_size[1]),$0.y/Double(f.image_size[1]),$0.confidence) },(normalizer.lastCrop?.side ?? 2)/(2*Double(f.image_size[1])),src)
            for (index,frame) in try live.push(frameIndex:i,coco17:kp,imageWidth:f.image_size[0],imageHeight:f.image_size[1],observerSource:i==30 ? nil : src,payload:i) {
                if index==30 { XCTAssertNil(frame.motionObservation) }
                if index==31 {
                    let input=try XCTUnwrap(inputs[index]);let raw=try XCTUnwrap(frame.raw)
                    var fresh=ExerciseMotionObserver(configuration:config(.G))
                    let expected=fresh.update(raw:raw,screen2D:input.0,modelToImageScale:input.1,source:input.2,flush:false)
                    assertPose(frame.motionObservation?.candidate,expected.candidate);checked=true
                }
            }
        }
        XCTAssertTrue(checked)
    }

    func testOptionalOnlineProportionsResetAcrossSourceSessions() {
        let p:[SIMD3<Double>] = [[0,0,0],[0.08,0.02,0],[0.1,0.25,0.01],[0.12,0.48,0],[-0.08,0.02,0],[-0.1,0.25,0.01],[-0.12,0.48,0],[0,-0.2,0],[0,-0.4,0],[0,-0.45,0],[0,-0.52,0],[-0.2,-0.36,0],[-0.35,-0.15,0],[-0.45,0.05,0],[0.2,-0.36,0],[0.35,-0.15,0],[0.45,0.05,0]]
        let screen=p.map { SIMD3($0.x+0.5,$0.y+0.55,0.9) }
        var observer=ExerciseMotionObserver(configuration:.init(exercise:"pushup",variant:.G,profile:nil,fixedCameraAssertion:false,onlineCalibration:true))
        var result:ExerciseMotionObserver.Output?
        for i in 0..<60 { result=observer.update(raw:p,screen2D:screen,modelToImageScale:1,source:source(i),flush:false) }
        XCTAssertEqual(result?.details["online_profile_applied"] as? Bool,true)
        let reset=observer.update(raw:p,screen2D:screen,modelToImageScale:1,source:source(0,session:2),flush:false)
        XCTAssertEqual(reset.details["online_profile_applied"] as? Bool,false)
        XCTAssertEqual(reset.details["online_profile_samples"] as? Int,1)
        XCTAssertEqual(reset.details["personal_profile_applied"] as? Bool,false)
    }

    func testStandaloneDiagnosticsRetainRolesContactsPredictionAndUncalibratedScores() throws {
        let f=try MotionAGFormerLiveTests().fixture()
        let kp=f.coco17[0].map { PoseKeypoint(x:$0[0],y:$0[1],confidence:$0[2]) }
        var screen=try PoseCoordinateTransforms.coco17ToH36M17(kp).map { SIMD3($0.x/480,$0.y/480,$0.confidence) }
        screen[3].z=1.2;screen[4].z = .nan
        let raw=screen.map { SIMD3($0.x,$0.y,0) }
        var observer=ExerciseMotionObserver(configuration:config(.G))
        let output=observer.update(raw:raw,screen2D:screen,modelToImageScale:1,source:source(0),flush:false)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let log=try ExerciseMotionObserverLog(directory:directory)
        log.write(output.dictionary);log.close()
        let lines=try String(contentsOf:log.url).split(separator:"\n")
        let decoded=try JSONSerialization.jsonObject(with:Data(lines[1].utf8)) as! [String:Any]
        let details=decoded["details"] as! [String:Any]
        XCTAssertEqual((details["roles"] as? [String])?.count,17)
        XCTAssertEqual((details["used_prediction"] as? [Bool])?.count,17)
        XCTAssertFalse((details["contacts"] as! [String:String]).isEmpty)
        let scores=details["observation_confidence_h36m"] as! [Any]
        XCTAssertEqual(scores.count,17);XCTAssertEqual(scores[3] as? Double,1.2)
        let input=details["source_2d_height_normalized"] as! [[Any]]
        XCTAssertEqual(input.count,17);XCTAssertEqual(input[3][0] as? Double,screen[3].x)
        XCTAssertEqual(input[3][2] as? Double,1.2)
        XCTAssertTrue(input[4][2] is NSNull)
        XCTAssertEqual(details["model_to_image_scale"] as? Double,1)
        XCTAssertTrue(scores[4] is NSNull)
        XCTAssertEqual(details["confidence_semantics"] as? String,"retained_detector_scores_not_accuracy_probabilities")
        XCTAssertEqual(decoded["adopted_for_feedback"] as? Bool,false)
    }

}
