import XCTest
@testable import CalibrationEngineKit

final class FormPraiseEvidenceTests: XCTestCase {
    private func point(_ x: Double, _ y: Double, _ confidence: Double = 0.95) -> PoseKeypoint {
        .init(x:x,y:y,confidence:confidence)
    }
    private func rowPose(shrug: Bool, missingFace: Bool = false) -> [PoseKeypoint] {
        var p=[PoseKeypoint](repeating:point(0,0),count:17)
        for (i,x,y) in [(3,shrug ? 305.0 : 330,shrug ? 195.0 : 180),(5,300,200),(7,200,150),
                         (9,220,210),(11,150,300),(13,120,370),(15,100,450)] {
            p[i]=point(x,y);p[i+1]=point(x,y)
        }
        p[0]=point(p[3].x+20,p[3].y)
        if missingFace { p[0].confidence=0;p[3].confidence=0;p[4].confidence=0 }
        return p
    }
    private func tracker() -> FormWarningTracker {
        let tracker=FormWarningTracker(exercise:.barbellRow)
        tracker.row.shrugEnabled=true
        tracker.common.enabledFeedbackKeys=["row_shrug","praise_fixed","praise_good"]
        return tracker
    }
    @discardableResult
    private func rep(_ tracker: FormWarningTracker, index: Int, shrug: Bool, missingMiddleFace: Bool = false) -> FormRepReport {
        for step in 0..<3 {
            tracker.observe(frameIndex:(index-1)*3+step,
                coco17:rowPose(shrug:step == 1 && shrug,missingFace:step == 1 && missingMiddleFace),
                phase:["top","bottom","ascending"][step])
            if step == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
        }
        return tracker.finishRep(repIndex:index)
    }
    private func establishSpokenShrug(_ tracker: FormWarningTracker) {
        XCTAssertTrue(rep(tracker,index:1,shrug:true).warnings.contains("row_shrug"))
        XCTAssertEqual(rep(tracker,index:2,shrug:true).spoken,"row_shrug")
        _=tracker.drainEvents()
    }
    func testMissingRuleSpecificObservationDoesNotProveCorrection() {
        let tracker=tracker();establishSpokenShrug(tracker)
        let report=rep(tracker,index:3,shrug:true,missingMiddleFace:true)
        XCTAssertEqual(report.metrics2D["ear_shoulder_drop"],0)
        XCTAssertFalse(report.warnings.contains("row_shrug"))
        XCTAssertNotEqual(report.spoken,"praise_fixed","missing the prior rule's measured interval is not observed correction")
        XCTAssertEqual(report.spoken,"praise_good","generic encouragement keeps its existing meaning and eligibility")
        XCTAssertFalse(tracker.drainEvents().contains { $0.key == "praise_fixed" })
    }
    func testFullyObservedCorrectionStillGetsSpecificPraise() {
        let tracker=tracker();establishSpokenShrug(tracker)
        XCTAssertEqual(rep(tracker,index:3,shrug:false).spoken,"praise_fixed")
        XCTAssertEqual(tracker.drainEvents(),[FormFeedbackEvent(key:"praise_fixed",n:nil)])
    }
    func testGenericEncouragementStillAppliesWithoutAnyPriorWarning() {
        let tracker=tracker()
        XCTAssertEqual(rep(tracker,index:1,shrug:false).spoken,"praise_good")
    }
    @discardableResult
    private func run(_ tracker: FormWarningTracker, index: Int, frame: (Int)->[PoseKeypoint]) -> FormRepReport {
        for step in 0..<3 {
            tracker.observe(frameIndex:(index-1)*3+step,coco17:frame(step),phase:["top","bottom","ascending"][step])
            if step == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
        }
        return tracker.finishRep(repIndex:index)
    }
    private func swingPose(_ swing: Bool) -> [PoseKeypoint] {
        var p=rowPose(shrug:false)
        if swing {
            for i in [5,6] { p[i]=point(200,100) }
            for i in [3,4] { p[i]=point(230,80) };p[0]=point(250,80)
        }
        return p
    }
    func testDefaultTorsoWarningCannotBeClearedByMissingMiddleGeometry() {
        let tracker=FormWarningTracker(exercise:.barbellRow)
        XCTAssertEqual(run(tracker,index:1,frame:{ self.swingPose($0 == 1) }).spoken,"row_torso_swing")
        let report=run(tracker,index:2) { step in
            var p=self.swingPose(false)
            if step == 1 { p[5]=p[11];p[6]=p[12] } // confident but degenerate trunk: nil metric
            return p
        }
        XCTAssertEqual(report.metrics2D["torso_max"],report.metrics2D["torso_min"])
        XCTAssertNotEqual(report.spoken,"praise_fixed")
    }
    func testMissingOppositeSideViewEvidenceDoesNotProveCorrection() {
        let tracker=FormWarningTracker(exercise:.barbellRow)
        XCTAssertEqual(run(tracker,index:1,frame:{ self.swingPose($0 == 1) }).spoken,"row_torso_swing")
        let report=run(tracker,index:2) { step in
            var p=self.swingPose(false);if step == 1 { p[6].confidence=0 };return p
        }
        XCTAssertNotEqual(report.spoken,"praise_fixed")
    }
    func testThresholdChangeDoesNotCountAsMeasuredImprovement() {
        let tracker=FormWarningTracker(exercise:.barbellRow)
        XCTAssertEqual(run(tracker,index:1,frame:{ self.swingPose($0 == 1) }).spoken,"row_torso_swing")
        tracker.row.torsoSwingRangeDegrees=100
        XCTAssertNotEqual(run(tracker,index:2,frame:{ self.swingPose($0 == 1) }).spoken,"praise_fixed")
    }
    func testSideSwitchDoesNotCountAsSameMeasuredIssue() {
        let tracker=FormWarningTracker(exercise:.barbellRow)
        XCTAssertEqual(run(tracker,index:1,frame:{ self.swingPose($0 == 1) }).spoken,"row_torso_swing")
        let report=run(tracker,index:2) { _ in
            var p=self.swingPose(false)
            for i in [3,5,7,9,11,13,15] { p[i].confidence=0.4 };return p
        }
        XCTAssertEqual(report.side,"right")
        XCTAssertNotEqual(report.spoken,"praise_fixed")
    }
    func testUnsupportedCachedFacingDoesNotBecomeTrustedFromAmbiguousFace() {
        let tracker=FormWarningTracker(exercise:.barbellRow)
        let first=run(tracker,index:1) { step in
            var p=self.swingPose(step == 1)
            p[0].x = step == 0 ? .infinity : p[3].x+0.5
            return p
        }
        XCTAssertEqual(first.spoken,"row_torso_swing")
        let next=run(tracker,index:2) { _ in
            var p=self.swingPose(false);p[0].x=p[3].x+0.5;return p
        }
        XCTAssertNotEqual(next.spoken,"praise_fixed")
    }
    func testRollingBaselineReplacementDoesNotProveCorrection() {
        let tracker=FormWarningTracker(exercise:.barbellRow)
        tracker.common.baselineRepCount=1;tracker.common.cooldownReps=0
        tracker.common.enabledFeedbackKeys=["row_short_pull","praise_fixed"]
        for index in 1...101 {
            let report=run(tracker,index:index) { _ in
                var p=self.rowPose(shrug:false)
                if index>1 { for i in [7,8] { p[i]=self.point(320,240) } }
                return p
            }
            if index == 101 { XCTAssertEqual(report.spoken,"row_short_pull") }
        }
        let next=run(tracker,index:102) { _ in
            var p=self.rowPose(shrug:false);for i in [7,8] { p[i]=self.point(320,240) };return p
        }
        XCTAssertFalse(next.warnings.contains("row_short_pull"))
        XCTAssertNotEqual(next.spoken,"praise_fixed","only the capped first-N baseline changed")
    }
    func testReferenceOnlyHeadWarningCannotBePreviousPerRepSpokenRule() {
        for key in ["pushup_head_drop","pushup_head_up","row_head_up"] {
            XCTAssertEqual(FormWarningTracker.grade(of:key),.reference)
        }
        let tracker=FormWarningTracker(exercise:.pushUp)
        tracker.common.enabledFeedbackKeys=["pushup_head_drop","praise_fixed","praise_good"]
        let report=run(tracker,index:1) { step in
            var p=[PoseKeypoint](repeating:self.point(0,0),count:17)
            for (i,x,y) in [(3,330.0,step == 1 ? 300.0 : 180),(5,300,200),(7,300,250),(9,300,300),
                            (11,150,200),(13,75,200),(15,0,200)] { p[i]=self.point(x,y);p[i+1]=self.point(x,y) }
            p[0]=self.point(p[3].x+20,p[3].y);return p
        }
        XCTAssertTrue(report.warnings.contains("pushup_head_drop"))
        XCTAssertNil(report.spoken)
        XCTAssertFalse(tracker.drainEvents().contains { $0.key == "pushup_head_drop" && $0.scope == .rep })
    }

    func testFacingChangeCandidateDoesNotProveCorrection() {
        let tracker=FormWarningTracker(exercise:.barbellRow)
        XCTAssertEqual(run(tracker,index:1,frame:{ self.swingPose($0 == 1) }).spoken,"row_torso_swing")
        let report=run(tracker,index:2) { step in
            var p=self.swingPose(false)
            if step == 1 { p[0].x=p[3].x-20 }
            return p
        }
        XCTAssertEqual(report.metrics2D["torso_min"],report.metrics2D["torso_max"],"warning hysteresis still holds original direction")
        XCTAssertNotEqual(report.spoken,"praise_fixed")
    }

    func testIncompletePriorPositiveCannotSupportSpecificCorrectionPraise() {
        let tracker=FormWarningTracker(exercise:.barbellRow)
        let first=run(tracker,index:1) { step in
            var p=self.swingPose(step == 2)
            if step == 1 { p[5]=p[11];p[6]=p[12] }
            return p
        }
        XCTAssertEqual(first.spoken,"row_torso_swing","the warning decision remains unchanged")
        XCTAssertNotEqual(run(tracker,index:2,frame:{ _ in self.swingPose(false) }).spoken,"praise_fixed")
    }

    private func row3D(elbowBehind: Double) -> [SIMD3<Double>] {
        var j=[SIMD3<Double>](repeating:.zero,count:17)
        j[1]=[-0.1,0,0];j[4]=[0.1,0,0];j[8]=[0,-0.5,0];j[10]=[0,-0.7,0]
        j[2]=[-0.1,0.4,0];j[3]=[-0.1,0.8,0];j[5]=[0.1,0.4,0];j[6]=[0.1,0.8,0]
        j[11]=[0.2,-0.5,0];j[14]=[-0.2,-0.5,0]
        j[12]=[0.2,-0.3,elbowBehind];j[15]=[-0.2,-0.3,elbowBehind]
        j[13]=[0.2,-0.1,elbowBehind];j[16]=[-0.2,-0.1,elbowBehind]
        return j
    }
    func testHistorical3DSubsetCannotCertifyCompleteReference() {
        for omitBaselineFrame in [true,false] {
            let tracker=FormWarningTracker(exercise:.barbellRow)
            tracker.common.form3DRequired=true;tracker.common.baselineRepCount=1;tracker.common.cooldownReps=0
            tracker.common.enabledFeedbackKeys=["row_short_pull","praise_fixed"]
            var reports=[FormRepReport]()
            for rep in 1...4 {
                for step in 0..<3 {
                    tracker.observe(frameIndex:(rep-1)*3+step,coco17:rowPose(shrug:false),
                        pose3D:row3D(elbowBehind:rep == 1 || rep == 4 ? 0.2 : 0),
                        pose3DState:omitBaselineFrame && rep == 1 && step == 1 ? .bad3D : .ok,
                        phase:["top","bottom","ascending"][step])
                    if step == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
                }
                reports.append(tracker.finishRep(repIndex:rep))
            }
            XCTAssertEqual(reports[2].spoken,"row_short_pull","legacy warning still uses its original enough3D gate")
            if omitBaselineFrame {
                XCTAssertNotEqual(reports[3].spoken,"praise_fixed","a complete current rep cannot heal a missing historical source frame")
            } else { XCTAssertEqual(reports[3].spoken,"praise_fixed") }
        }
    }

    func testFiniteOK3DRowRequiresObservedElbowSupport() {
        // -1: full support; 1/4: missing relevant elbow in baseline/current; 5: unrelated wrist absent.
        for loss in [-1,1,4,5] {
            let tracker=FormWarningTracker(exercise:.barbellRow)
            tracker.common.form3DRequired=true;tracker.common.baselineRepCount=1;tracker.common.cooldownReps=0
            tracker.common.enabledFeedbackKeys=["row_short_pull","praise_fixed"]
            var reports=[FormRepReport]()
            for rep in 1...4 {
                for step in 0..<3 {
                    var pose=rowPose(shrug:false)
                    if step == 1 && rep == loss { pose[7].confidence=0;pose[8].confidence=0 }
                    if step == 1 && rep == 4 && loss == 5 { pose[9].confidence=0;pose[10].confidence=0 }
                    tracker.observe(frameIndex:(rep-1)*3+step,coco17:pose,
                        pose3D:row3D(elbowBehind:rep == 1 || rep == 4 ? 0.2 : 0),pose3DState:.ok,
                        phase:["top","bottom","ascending"][step])
                    if step == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
                }
                reports.append(tracker.finishRep(repIndex:rep))
            }
            XCTAssertEqual(reports[2].spoken,"row_short_pull")
            XCTAssertEqual(reports[3].states3D,["ok":3])
            if loss == -1 || loss == 5 { XCTAssertEqual(reports[3].spoken,"praise_fixed") }
            else { XCTAssertNotEqual(reports[3].spoken,"praise_fixed","finite3D .ok does not prove elbow source support: rep \(loss)") }
        }
    }
    private func plank3D(bent: Bool) -> [SIMD3<Double>] {
        var j=row3D(elbowBehind:0)
        j[8]=[0,0,-0.5];j[10]=[0,0,-0.6]
        j[3]=[-0.1,0,1];j[6]=[0.1,0,1];j[2]=[-0.1,0,0.5];j[5]=[0.1,0,0.5]
        j[11]=[0.2,0,-0.5];j[14]=[-0.2,0,-0.5]
        j[12]=[0.2,0.2,-0.5];j[15]=[-0.2,0.2,-0.5]
        j[13]=bent ? [0.35,0.1,-0.5] : [0.2,0.4,-0.5]
        j[16]=bent ? [-0.35,0.1,-0.5] : [-0.2,0.4,-0.5]
        return j
    }
    func testFiniteOK3DPushupRequiresObservedWristButNot2DFacing() {
        for loss in [-1,1,4,5] {
            let tracker=FormWarningTracker(exercise:.pushUp)
            tracker.common.form3DRequired=true;tracker.common.baselineRepCount=1;tracker.common.cooldownReps=0
            tracker.common.enabledFeedbackKeys=["pushup_shallow","praise_fixed"]
            var reports=[FormRepReport]()
            for rep in 1...4 {
                for step in 0..<3 {
                    var pose=rowPose(shrug:false)
                    if step == 1 && rep == loss { pose[9].confidence=0;pose[10].confidence=0 }
                    if rep == 4 && loss == 5 { pose[0].confidence=0;pose[3].confidence=0;pose[4].confidence=0 }
                    tracker.observe(frameIndex:(rep-1)*3+step,coco17:pose,
                        pose3D:plank3D(bent:(rep == 1 || rep == 4) && step == 1),pose3DState:.ok,
                        phase:["top","bottom","ascending"][step])
                    if step == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
                }
                reports.append(tracker.finishRep(repIndex:rep))
            }
            XCTAssertEqual(reports[2].spoken,"pushup_shallow")
            XCTAssertEqual(reports[3].states3D,["ok":3])
            if loss == -1 || loss == 5 { XCTAssertEqual(reports[3].spoken,"praise_fixed") }
            else { XCTAssertNotEqual(reports[3].spoken,"praise_fixed","finite3D .ok does not prove wrist source support: rep \(loss)") }
        }
    }

    func testObservedH36MMappingRequiresEveryRootAndThoraxConstituent() throws {
        var pose=rowPose(shrug:false)
        pose[11].confidence=0.1;pose[12].confidence=0.95
        let converted=try PoseCoordinateTransforms.coco17ToH36M17(pose)
        XCTAssertGreaterThan(converted[0].confidence,0.3,"averaged root confidence alone hides the unsupported left hip")
        let supported=FormCorrectionEvidence.observedH36MJoints(pose,minimumConfidence:0.3)
        XCTAssertFalse(supported.contains(0));XCTAssertFalse(supported.contains(7));XCTAssertFalse(supported.contains(4))
        XCTAssertTrue(supported.contains(1));XCTAssertTrue(supported.contains(8));XCTAssertTrue(supported.contains(13))
        pose=rowPose(shrug:false);pose[6].x = .infinity
        let badShoulder=FormCorrectionEvidence.observedH36MJoints(pose,minimumConfidence:0.3)
        XCTAssertFalse(badShoulder.contains(8));XCTAssertFalse(badShoulder.contains(7));XCTAssertFalse(badShoulder.contains(9))
        XCTAssertTrue(badShoulder.contains(0));XCTAssertTrue(badShoulder.contains(11))
        pose=rowPose(shrug:false);pose[9].confidence = .infinity
        let badScore=FormCorrectionEvidence.observedH36MJoints(pose,minimumConfidence:0.3)
        XCTAssertFalse(badScore.contains(13));XCTAssertTrue(badScore.contains(12))
    }

    func testObservedSupportMatchesActualConverterDependenciesForEveryCOCOJoint() throws {
        let all=Set(0..<17)
        let original=rowPose(shrug:false)
        let baseline=try PoseCoordinateTransforms.coco17ToH36M17(original)
        for source in 0..<17 {
            var shifted=original;shifted[source].x += 100
            let mapped=try PoseCoordinateTransforms.coco17ToH36M17(shifted)
            let affected=Set((0..<17).filter { mapped[$0].x != baseline[$0].x })
            var low=original;low[source].confidence=0.29
            XCTAssertEqual(FormCorrectionEvidence.observedH36MJoints(low,minimumConfidence:0.3),all.subtracting(affected),"source joint \(source)")
            low[source].confidence = .nan
            XCTAssertEqual(FormCorrectionEvidence.observedH36MJoints(low,minimumConfidence:0.3),all.subtracting(affected),"NaN source joint \(source)")
            low[source].confidence=0.3
            XCTAssertEqual(FormCorrectionEvidence.observedH36MJoints(low,minimumConfidence:0.3),all,"unchanged inclusive native threshold")
        }
    }

}
