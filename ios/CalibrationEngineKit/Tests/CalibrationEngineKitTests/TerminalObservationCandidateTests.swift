import XCTest
@testable import CalibrationEngineKit

final class TerminalObservationCandidateTests: XCTestCase {
    func original(_ rep: Int = 1, epoch: Int = 1, exercise: String = "pushup") -> TerminalObservationCandidate.Original {
        .init(epoch: epoch, exercise: exercise, rep: rep, startFrame: rep*100, endFrame: rep*100+10, side: "left", threshold: 10,
              originalMaxima: exercise == "squat" ? ["knee":130, "hip":120] : ["elbow":130])
    }
    func frame(_ o: TerminalObservationCandidate.Original, _ i: Int, angle: Double = 170) -> TerminalObservationCandidate.Frame {
        .init(epoch: o.epoch, frame: o.endFrame+i, sourceIndex: o.endFrame+i, sourceTime: Double(o.rep)*2+Double(i)*0.05,
              hostTime: Double(o.rep)*2+Double(i)*0.05, activeRepStart: nil, side: o.side, phase: "top", required2D: true,
              sideView: true, state: "ok", flushed: false, coordinateKey: "640/480/0/front",
              assessmentAngles: o.exercise == "squat" ? ["knee":angle, "hip":angle] : ["elbow":angle], rawAngles: ["elbow":180])
    }
    func open(_ engine: inout TerminalObservationCandidate, _ o: TerminalObservationCandidate.Original) {
        engine.begin(o, hostTime: Double(o.rep)*2)
        engine.observe(frame(o,0))
    }
    func stable(_ engine: inout TerminalObservationCandidate, _ o: TerminalObservationCandidate.Original, angle: Double = 170) {
        for i in 1...7 { engine.observe(frame(o,i,angle:angle)) }
    }
    func boundary(_ engine: inout TerminalObservationCandidate, _ o: TerminalObservationCandidate.Original) {
        var next=frame(o,8);next.activeRepStart=o.endFrame+8
        // The new rep's first sample is invalid/opposite. It must close the previous window first.
        next.side="right";next.required2D=false;next.assessmentAngles=[:]
        engine.observe(next)
    }
    func references(_ engine: inout TerminalObservationCandidate) {
        for rep in 1...3 {
            let o=original(rep);open(&engine,o);stable(&engine,o);boundary(&engine,o)
            let report=engine.drain().last!
            XCTAssertEqual(report.coverage,"observed_stable_top_window")
            XCTAssertEqual(report.assessment,"withheld")
            XCTAssertEqual(report.referenceCount,rep-1)
        }
    }
    func testCandidateUsesOnlySameProtocolPastReferencesAndPreservesLowStableDeficit() {
        var e=TerminalObservationCandidate();e.start(epoch:1);references(&e)
        let o=original(4);open(&e,o);stable(&e,o,angle:140);boundary(&e,o)
        let r=e.drain().last!
        XCTAssertEqual(r.referencePlateauMaxima,["elbow":170])
        XCTAssertEqual(r.relativeDeficits,["elbow":30])
        XCTAssertEqual(r.assessment,"relative_terminal_deficit_observed")
        XCTAssertEqual(r.original.originalMaxima,["elbow":130]) // immutable original interval
        XCTAssertFalse(r.scope.contains("correct_form"))
    }
    func testConstantLowFirstRepsNeverBecomeCorrectFormOrWarnWithoutReference() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        for rep in 1...4 {
            let o=original(rep);open(&e,o);stable(&e,o,angle:140);boundary(&e,o)
            let r=e.drain().last!
            XCTAssertEqual(r.terminalPlateauMaxima,["elbow":140])
            XCTAssertEqual(r.assessment,rep<4 ? "withheld" : "relative_deficit_not_observed")
            XCTAssertTrue(r.scope.contains("not_full_extension"))
        }
    }
    func testObservedPlateauIsProvisionalAndLaterExtensionRemainsVisible() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();open(&e,o);stable(&e,o,angle:140)
        XCTAssertNil(e.drain().last)
        for i in 8...15 { e.observe(frame(o,i,angle:170)) }
        var next=frame(o,16);next.phase="lowering";e.observe(next)
        let r=e.drain().last!
        XCTAssertEqual(r.terminalPlateauMaxima,["elbow":170])
        XCTAssertEqual(r.closure,"top_phase_exited")
    }
    func testEarlySpikeIsRetainedAsDiagnosticButNotLastStableTerminalReference() {
        var e=TerminalObservationCandidate();e.start(epoch:1);references(&e)
        let o=original(4);open(&e,o);e.observe(frame(o,1,angle:180))
        for i in 2...9 { e.observe(frame(o,i,angle:140)) }
        var next=frame(o,10);next.phase="lowering";e.observe(next)
        let r=e.drain().last!
        XCTAssertEqual(r.observedTopMaxima,["elbow":180])
        XCTAssertEqual(r.terminalPlateauMaxima,["elbow":140])
        XCTAssertEqual(r.assessment,"withheld")
        XCTAssertEqual(r.coverage,"ambiguous_terminal_observation")
        XCTAssertEqual(r.allFollowupMaxima,["elbow":180])
        XCTAssertEqual(r.rawFollowupMaxima,["elbow":180])
    }
    func testNextActualBeginClosesBeforeItsInvalidGeometryAndCannotJoinPriorWindow() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();open(&e,o);stable(&e,o);boundary(&e,o)
        let r=e.drain().last!
        XCTAssertEqual(r.closure,"next_rep_started")
        XCTAssertEqual(r.coverage,"observed_stable_top_window")
        XCTAssertEqual(r.topFrames,7)
        XCTAssertEqual(r.lastSourceTime,2.35)
    }
    func testIncompleteNextBeginWithholdsAndIsNotAddedAsReference() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();open(&e,o);e.observe(frame(o,1));boundary(&e,o)
        XCTAssertEqual(e.drain().last?.coverage,"incomplete_terminal_observation")
        let o2=original(2);open(&e,o2);stable(&e,o2);boundary(&e,o2)
        XCTAssertEqual(e.drain().last?.referenceCount,0)
    }
    func testInvalidityNeverDropsBadSamplesToProduceAValidTerminalWindow() {
        let invalidators: [(inout TerminalObservationCandidate.Frame)->Void] = [
            {$0.required2D=false}, {$0.sideView=nil}, {$0.sideView=false}, {$0.state="tracking_lost"}, {$0.state="bad_3d"},
            {$0.assessmentAngles=[:]}, {$0.side="right"}, {$0.flushed=true}, {$0.sourceTime=nil},
            {$0.sourceIndex=nil}, {$0.coordinateKey="rotated"}, {$0.phase="unknown"}
        ]
        for invalidate in invalidators {
            var e=TerminalObservationCandidate();e.start(epoch:1)
            let o=original();open(&e,o);stable(&e,o)
            var f=frame(o,8);invalidate(&f);e.observe(f)
            let r=e.drain().last!
            XCTAssertEqual(r.assessment,"withheld")
            XCTAssertEqual(r.coverage,"incomplete_terminal_observation")
            XCTAssertTrue(r.referencePlateauMaxima.isEmpty)
        }
    }
    func testDuplicateSourceGapAndTimeoutAreExplicitWithheld() {
        for mode in 0..<4 {
            var e=TerminalObservationCandidate();e.start(epoch:1)
            let o=original();open(&e,o);e.observe(frame(o,1))
            var f=frame(o,2)
            if mode==0 { f.sourceTime=2.05 }
            if mode==1 { f.sourceIndex=o.endFrame+1 }
            if mode==2 { f.sourceTime=2.4 }
            if mode==3 { f.hostTime=4 }
            e.observe(f)
            XCTAssertEqual(e.drain().last?.assessment,"withheld")
        }
    }
    func testWatchdogWithoutNewFramesClosesPendingAndCannotExpireLaterRep() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();open(&e,o);stable(&e,o)
        e.expire(epoch:1,rep:1,hostTime:3.6)
        XCTAssertEqual(e.drain().last?.closure,"watchdog_timeout")
        let next=original(2);open(&e,next)
        e.expire(epoch:1,rep:1,hostTime:10)
        XCTAssertEqual(e.pendingRep,2)
    }
    func testSetEndResetAndStaleEpochNeverMixReferenceOrPendingOwnership() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();open(&e,o);stable(&e,o);e.end(epoch:1,reason:"set_end",hostTime:2.4)
        XCTAssertEqual(e.drain().last?.coverage,"observed_stable_top_window")
        e.start(epoch:2)
        let new=original(2,epoch:2);open(&e,new)
        e.observe(frame(o,8));e.end(epoch:1,reason:"set_end",hostTime:2.4)
        XCTAssertEqual(e.pendingRep,2);XCTAssertEqual(e.rejectedStaleFrames,1)
        e.begin(o,hostTime:5)
        XCTAssertEqual(e.drain().last?.assessment,"withheld");XCTAssertEqual(e.pendingRep,2)
        e.start(epoch:3)
        XCTAssertEqual(e.drain().last?.closure,"reset")
    }
    func testSquatRequiresBothNativeDependentAnglesAndSameSideReferences() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original(exercise:"squat");open(&e,o)
        var f=frame(o,1);f.assessmentAngles.removeValue(forKey:"hip");e.observe(f)
        XCTAssertEqual(e.drain().last?.assessment,"withheld")
    }
    func testRawHighAngleCannotReplaceUnavailableNativeAssessment() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();open(&e,o)
        var f=frame(o,1);f.rawAngles=["elbow":180];f.assessmentAngles=[:]
        e.observe(f)
        XCTAssertEqual(e.drain().last?.assessment,"withheld")
    }
    func testMalformedConfigAndOriginalNeverOpenAnOperation() {
        var bad=TerminalObservationCandidate.Config();bad.timeoutSeconds = .nan
        var e=TerminalObservationCandidate(config:bad);e.start(epoch:1);open(&e,original())
        XCTAssertNil(e.pendingRep)
        var normal=TerminalObservationCandidate();normal.start(epoch:1)
        var o=original();o.threshold = .infinity;normal.begin(o,hostTime:2)
        XCTAssertNil(normal.pendingRep)
    }
    func testFlushedOriginalEndCannotBecomeAnAnchor() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();e.begin(o,hostTime:2)
        var end=frame(o,0);end.flushed=true;e.observe(end)
        XCTAssertEqual(e.drain().last?.reasons,["clamped_or_reset_flush"])
        XCTAssertNil(e.pendingRep)
    }
    func testNormalLongTopPauseCanBeWithheldByUntunedOperationalTimeout() {
        var e=TerminalObservationCandidate();e.start(epoch:1);references(&e)
        let o=original(4);open(&e,o);stable(&e,o)
        e.expire(epoch:1,rep:4,hostTime:9.6)
        let r=e.drain().last!
        XCTAssertEqual(r.assessment,"withheld")
        XCTAssertEqual(r.reasons,["timeout_without_new_source"])
        XCTAssertEqual(r.terminalPlateauMaxima,["elbow":170])
    }
    func testClosedWindowAndOppositeSideCannotLeakFutureReference() {
        var e=TerminalObservationCandidate();e.start(epoch:1);references(&e)
        let o=original(4);open(&e,o);stable(&e,o,angle:140);boundary(&e,o)
        XCTAssertEqual(e.drain().last?.relativeDeficits,["elbow":30])
        e.observe(frame(o,9,angle:180)) // this window is closed; no retrospective improvement
        let next=original(5);open(&e,next);stable(&e,next,angle:140);boundary(&e,next)
        XCTAssertEqual(e.drain().last?.referencePlateauMaxima,["elbow":170])
        var right=original(6);right.side="right"
        open(&e,right);stable(&e,right,angle:140);boundary(&e,right)
        let r=e.drain().last!
        XCTAssertEqual(r.referenceCount,0)
        XCTAssertEqual(r.assessment,"withheld")
    }

    func testDelayedNextBeginCannotBypassDeadlineAndHostIsNotMotionTime() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();open(&e,o);stable(&e,o)
        var next=frame(o,8);next.activeRepStart=o.endFrame+8;next.hostTime=20
        e.observe(next)
        XCTAssertEqual(e.drain().last?.reasons,["timeout"])
        var independent=TerminalObservationCandidate();independent.start(epoch:1)
        independent.begin(o,hostTime:1000)
        for i in 0...7 { var f=frame(o,i);f.hostTime=1000+Double(i)*0.06;independent.observe(f) }
        var exit=frame(o,8);exit.hostTime=1000.5;exit.activeRepStart=o.endFrame+8;independent.observe(exit)
        XCTAssertEqual(independent.drain().last?.coverage,"observed_stable_top_window")
    }
    func testCoordinateChangeBetweenRepsStartsIndependentReferenceContract() {
        var e=TerminalObservationCandidate();e.start(epoch:1);references(&e)
        let o=original(4);e.begin(o,hostTime:8)
        for i in 0...7 { var f=frame(o,i);f.coordinateKey="640/480/90/front";e.observe(f) }
        var next=frame(o,8);next.coordinateKey="640/480/90/front";next.activeRepStart=o.endFrame+8;e.observe(next)
        XCTAssertEqual(e.drain().last?.referenceCount,0)
    }

    func testLateSetEndCannotBeatQueuedWatchdogAndShortExtensionCannotBeLabelledBad() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();open(&e,o);stable(&e,o)
        e.end(epoch:1,reason:"set_end",hostTime:10)
        XCTAssertEqual(e.drain().last?.reasons,["set_end_without_fresh_operational_deadline"])
        e.start(epoch:1);references(&e)
        let later=original(4);open(&e,later)
        var high=frame(later,1,angle:180);high.phase="ascending";e.observe(high)
        for i in 2...9 { e.observe(frame(later,i,angle:140)) }
        var exit=frame(later,10);exit.phase="lowering";e.observe(exit)
        let r=e.drain().last!
        XCTAssertEqual(r.allFollowupMaxima,["elbow":180])
        XCTAssertEqual(r.terminalPlateauMaxima,["elbow":140])
        XCTAssertEqual(r.assessment,"withheld")
        XCTAssertEqual(r.coverage,"ambiguous_terminal_observation")
    }

    func testExplicitSetEndTailDoesNotPoisonGenuineQueuedObservationButImplicitFlushDoes() {
        var e=TerminalObservationCandidate();e.start(epoch:1)
        let o=original();open(&e,o)
        for i in 1...6 { e.observe(frame(o,i)) }
        var clamped=frame(o,8);clamped.flushed=true;clamped.setEndFlushTail=true;e.observe(clamped)
        e.observe(frame(o,7)) // already captured, genuine nonflush delivery reaches MainActor later
        e.end(epoch:1,reason:"set_end",hostTime:2.4)
        XCTAssertEqual(e.drain().last?.coverage,"observed_stable_top_window")
        e.start(epoch:2)
        let next=original(2,epoch:2);open(&e,next)
        var implicit=frame(next,1);implicit.flushed=true;e.observe(implicit)
        XCTAssertEqual(e.drain().last?.reasons,["clamped_or_reset_flush"])
    }
    func testTrackingLossBetweenRepsInvalidatesPastReferenceIdentity() {
        var e=TerminalObservationCandidate();e.start(epoch:1);references(&e)
        var lost=frame(original(3),9);lost.state="tracking_lost";e.observe(lost)
        let o=original(4);open(&e,o);stable(&e,o);boundary(&e,o)
        XCTAssertEqual(e.drain().last?.referenceCount,0)
    }

}
