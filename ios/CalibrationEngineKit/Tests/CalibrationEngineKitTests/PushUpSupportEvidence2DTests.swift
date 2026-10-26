import XCTest
@testable import CalibrationEngineKit

final class PushUpSupportEvidence2DTests: XCTestCase {
    typealias Adapter = PushUpSupportEvidence2D
    func points(_ wristX: Double = 140, score: Double = 0.95) -> [PoseKeypoint] {
        var p = Array(repeating: PoseKeypoint(x: 100, y: 100, confidence: score), count: 17)
        for (i,x,y) in [(5,100.0,100.0),(6,120,100),(7,130,140),(8,160,140),(9,wristX,180),(10,180,180),(11,300,100),(12,320,100)] {
            p[i] = PoseKeypoint(x: x, y: y, confidence: score)
        }
        return p
    }
    func frame(_ t: Double, _ p: [PoseKeypoint]? = nil) -> Adapter.Frame {
        .init(keypoints: p ?? points(), sourcePTS: t, width: 640, height: 480, rotation: 0,
              epoch: "session/person/crop", supportActive: true, cameraEvidence: .controlledReplayAssertion)
    }
    func acquire(_ a: inout Adapter) { for t in [0.0,0.07,0.14,0.21] { _ = a.update(frame(t)) } }
    func testScoreAboveOneUsesRawSimCCThresholdWithoutProbabilityClamp() {
        var a = Adapter(enabled: true)
        _ = a.update(frame(0, points(score: 1.15)))
        let r = a.update(frame(0.07, points(score: 1.15)))
        XCTAssertTrue(r.corridor.left.assessmentEligible)
        XCTAssertEqual(r.corridor.left.raw.confidence, 1.15)
    }
    func testConfidenceAloneCannotSatisfyNeighborAndTemporalEvidence() {
        var a = Adapter(enabled: true)
        let first = a.update(frame(0)); XCTAssertFalse(first.evidence[0].temporalEvidenceConsistent)
        var p = points(); p[7].confidence = 0.1
        let r = a.update(frame(0.07,p)); XCTAssertFalse(r.evidence[0].neighborEvidenceConsistent)
        XCTAssertFalse(r.corridor.left.assessmentEligible)
    }
    func testRawJumpVetoThenCoherentRelocationImmediatelyBypassesSmoother() {
        var a = Adapter(enabled: true); acquire(&a)
        let moved = points(420)
        let jump = a.update(frame(0.28,moved))
        XCTAssertTrue(jump.corridor.left.inferred)
        let movedObserved = a.update(frame(0.35,moved))
        XCTAssertEqual(movedObserved.corridor.left.reason, .observedReleased)
        var smoother = OverlaySmoother(); _ = smoother.smooth(points(), at: 0)
        let smoothed = smoother.smooth(moved, at: 0.07)
        XCTAssertLessThan(smoothed[9].x, moved[9].x)
        XCTAssertEqual(movedObserved.display(over: smoothed)[9].x, moved[9].x)
    }
    func testUnknownCameraNeverAcquiresOrInfersContact() {
        var a = Adapter(enabled: true)
        for t in [0.0,0.07,0.14,0.21] { var f=frame(t); f.cameraEvidence = .unknown; XCTAssertNil(a.update(f).corridor.left.anchor) }
        var f=frame(0.28); f.cameraEvidence = .unknown; f.keypoints[9].confidence=0.1
        XCTAssertNil(a.update(f).corridor.left.displayPoint)
    }
    func testCurrentContactEligibilityLossClearsOldAnchor() {
        var a = Adapter(enabled: true); acquire(&a)
        var f=frame(0.28); f.supportActive=false; f.keypoints[9].confidence=0.1
        XCTAssertNil(a.update(f).corridor.left.displayPoint)
        f=frame(0.35); f.keypoints[9].confidence=0.1
        XCTAssertNil(a.update(f).corridor.left.anchor)
    }
    func testGeometryCropIdentityAndTimeChangesReset() {
        for mode in 0..<7 {
            var a=Adapter(enabled:true); acquire(&a); var f=frame(0.28)
            switch mode {
            case 0:f.width=1280
            case 1:f.height=720
            case 2:f.rotation=90
            case 3:f.epoch="newCrop"
            case 4:f.sourcePTS=1
            case 5:f.sourcePTS=0.1
            default:f.keypoints[11].x=1000; f.keypoints[12].x=1000
            }
            f.keypoints[9].confidence=0.1
            let r=a.update(f); XCTAssertTrue(r.reset); XCTAssertNil(r.corridor.left.anchor)
        }
    }
    func testInferredAndExpiredOnlyAffectDisplayAndAssessmentCopies() {
        var a=Adapter(enabled:true); acquire(&a); var f=frame(0.28)
        f.keypoints[9].confidence=0.1; let raw=f.keypoints
        let r=a.update(f)
        XCTAssertEqual(r.uncertainJoints,[9]); XCTAssertEqual(raw[9].confidence,0.1)
        XCTAssertEqual(r.assessment2D(raw)[9].confidence,0)
        XCTAssertTrue(r.assessment3D(Array(repeating: SIMD3(1,2,3), count:17))![13].x.isNaN)
        XCTAssertEqual(r.display(over:raw)[9].confidence,0.31)
        var last=r
        for t in [0.35,0.42,0.49,0.56,0.63] { f.sourcePTS=t; last=a.update(f) }
        XCTAssertNil(last.corridor.left.displayPoint)
        XCTAssertEqual(last.display(over:raw)[9].confidence,0)
        XCTAssertTrue(last.corridor.withholdSkeleton)
    }
    func testFrameOutputsRemainAlignedAcrossLaterUpdates() {
        var a=Adapter(enabled:true); acquire(&a); var f=frame(0.28); f.keypoints[9].confidence=0.1
        let delayed=a.update(f)
        _ = a.update(frame(0.35))
        let latest=a.update(frame(0.42))
        XCTAssertFalse(delayed.corridor.left.assessmentEligible)
        XCTAssertTrue(latest.corridor.left.assessmentEligible)
        XCTAssertEqual(delayed.corridor.sourcePTS,0.28)
        XCTAssertEqual(delayed.assessment2D(points())[9].confidence,0)
    }
    func testRawOKFrameWithInferredArmCannotPraiseOrEmitArmCandidate() {
        var j = [SIMD3<Double>](repeating: .zero, count: 17)
        j[1] = [-0.1,0,0]; j[4] = [0.1,0,0]
        j[8] = [0,0,-0.5]; j[7] = [0,0,-0.25]; j[10] = [0,0,-0.75]
        j[3] = [-0.1,0,1]; j[6] = [0.1,0,1]; j[2] = [-0.1,0,0.5]; j[5] = [0.1,0,0.5]
        j[11] = [0.15,0,-0.5]; j[12] = [0.15,0.25,-0.5]; j[13] = [0.15,0.5,-0.5]
        j[14] = [-0.15,0,-0.5]; j[15] = [-0.15,0.25,-0.5]; j[16] = [-0.15,0.5,-0.5]
        var a=Adapter(enabled:true); acquire(&a); var f=frame(0.28)
        f.keypoints[9].confidence=0.1; f.keypoints[10].confidence=0.1
        let r=a.update(f)
        XCTAssertEqual(r.assessmentState(.ok),.partial3D)
        XCTAssertEqual(r.invalid3DJoints,[12,13,15,16])
        let tracker=FormWarningTracker(exercise:.pushUp); tracker.common.form3DRequired=true
        for i in 0..<2 {
            tracker.observe(frameIndex:i,coco17:r.assessment2D(f.keypoints),pose3D:r.assessment3D(j),
                pose3DState:r.assessmentState(.ok),phase:i == 0 ? "descending" : "bottom")
            if i == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
        }
        let report=tracker.finishRep(repIndex:1)
        XCTAssertNil(report.spoken)
        XCTAssertFalse(tracker.drainEvents().contains { $0.key.hasPrefix("praise_") })
        var coaching=ExperimentalCoaching()
        let profile=ExperimentalCoaching.Profile(exercise:"pushup",variant:"approved_pushup",approved:true,
            upperArmRange:20...45,legExtensionDegrees:15,elbowFlexionDegrees:15,sustainSeconds:0.1)
        for t in [0.28,0.35,0.42] {
            let output=coaching.update(.init(time:t,exercise:"pushup",phase:"bottom",
                state:r.assessmentState(.ok)!.rawValue,raw:j,corrected:r.assessment3D(j),
                confidence:r.assessmentConfidence(Array(repeating:0.95,count:17)),invalid:r.invalid3DJoints,up:nil),profile:profile)
            XCTAssertFalse(output.metrics["leftElbowDeg"]!.available)
            XCTAssertFalse(output.metrics["leftUpperArmDeg"]!.available)
            XCTAssertEqual(output.candidates.first?.assessment,"withheld")
        }
        XCTAssertEqual(j[13],SIMD3(0.15,0.5,-0.5),"raw 3D preserved")
    }

    func testAssessmentCannotCertifyDifferentRawWristThanObservedOverlaySource() {
        var a=Adapter(enabled:true); acquire(&a); let r=a.update(frame(0.28))
        var raw=points(); raw[9].x=400
        XCTAssertEqual(r.assessment2D(raw)[9].confidence,0)
        XCTAssertEqual(raw[9].x,400)
        XCTAssertEqual(r.assessment2D(raw)[9].x,400,"no pose normalization")
    }

    func testExperimentReadinessIsAtomicAndResetCreatesNewGeneration() {
        let control=PushUpSupportExperimentControl()
        XCTAssertFalse(control.snapshot().eligible)
        control.markReady(); let before=control.snapshot()
        XCTAssertTrue(before.eligible)
        control.reset(); let after=control.snapshot()
        XCTAssertFalse(after.eligible); XCTAssertEqual(after.generation,before.generation+1)
        XCTAssertTrue(before.eligible,"old source snapshot cannot mutate with latest control")
    }

}
