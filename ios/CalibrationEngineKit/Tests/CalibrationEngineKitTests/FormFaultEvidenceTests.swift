import XCTest
@testable import CalibrationEngineKit

final class FormFaultEvidenceTests: XCTestCase {
    private func source(_ frame: Int, flush: Bool = false) -> FormFaultSource {
        .init(frame:frame,sourceIndex:frame,timeValue:Int64(frame),timeScale:50,session:"fixture",kind:"retained_fixture",flush:flush)
    }
    private func judge(_ exercise: FormExercise, _ metrics: [String:Double], history: [[String:Double]] = [],
                       configure: (FormWarningTracker) -> Void = { _ in }) -> ([String],[String:Any]) {
        let tracker = FormWarningTracker(exercise:exercise); configure(tracker)
        let trace = FormFaultJudge(traceID:"fixture/rep/1/2d",source:"2d",repIndex:1,exercise:exercise,metrics:metrics,
            aggregation:FormFaultAggregation(frames:[]),history:history.enumerated().map {
                FormFaultHistory(traceID:"prior/\($0.offset)",repIndex:$0.offset+1,metrics:$0.element)
            },common:tracker.common,squat:tracker.squat,row:tracker.row)
        var assessed = Set<String>()
        let fired = tracker.judge(metrics,history:history,repIndex:1,assessed:{ assessed = $0 },trace:trace)
        return (fired,trace.finish(fired:fired,assessed:assessed))
    }
    private func row(_ key: String, _ result: [String:Any]) -> [String:Any] {
        (result["rules"] as! [[String:Any]]).first { $0["rule"] as? String == key }!
    }
    func testActualFalseNilNotCalledAndQuietExecution() {
        let result = judge(.pushUp,["front_view_fraction":0,"hip_dev_max":0]).1
        XCTAssertEqual(row("pushup_hip_sag",result)["callState"] as? String,"false")
        XCTAssertEqual(row("pushup_head_drop",result)["callState"] as? String,"nil")
        XCTAssertEqual(row("pushup_hand_position",result)["callState"] as? String,"not_called")
        let quiet = judge(.pushUp,["front_view_fraction":0,"head_dev_change_min": -1]).1
        XCTAssertEqual(row("pushup_head_up",quiet)["executionEnabled"] as? Bool,true)
        XCTAssertEqual(row("pushup_head_up",quiet)["deliveryEnabled"] as? Bool,false)
        XCTAssertEqual(row("pushup_head_up",quiet)["rawFired"] as? Bool,true)
        XCTAssertEqual(row("squat_heel_rise",judge(.squat,[:]).1)["executionEnabled"] as? Bool,false)
    }
    func testLockoutORPreservesMissingOperandAndShortCircuit() {
        let falseMissing = row("squat_no_lockout",judge(.squat,["front_view_fraction":0,"knee_max":180]).1)
        XCTAssertEqual(falseMissing["callState"] as? String,"false")
        XCTAssertEqual(falseMissing["negativeOperandEvidence"] as? Bool,false)
        let ops = falseMissing["operands"] as! [[String:Any]]
        XCTAssertEqual(ops.count,2); XCTAssertTrue(ops[1]["result"] is NSNull)
        let trueMissing = row("squat_no_lockout",judge(.squat,["front_view_fraction":0,"knee_max":130],history:[["knee_max":180]]).1)
        XCTAssertEqual(trueMissing["rawFired"] as? Bool,true)
        XCTAssertEqual(trueMissing["positiveOperandEvidence"] as? Bool,true)
        XCTAssertEqual((trueMissing["operands"] as! [[String:Any]]).count,1) // actual Swift OR short circuit
    }
    func testNonfiniteThresholdCannotProveNegative() {
        let result = judge(.pushUp,["front_view_fraction":0,"hip_dev_max":0]) { $0.pushUp.hipSagDeviation = .nan }.1
        let value = row("pushup_hip_sag",result)
        XCTAssertEqual(value["callState"] as? String,"false") // preserve legacy comparison
        XCTAssertEqual(value["negativeOperandEvidence"] as? Bool,false)
        XCTAssertEqual((value["operands"] as! [[String:Any]])[0]["finiteThreshold"] as? Bool,false)
        let manual = judge(.barbellRow,["front_view_fraction":0,"torso_min":0,"torso_max":1]) { $0.row.torsoSwingRangeDegrees = .nan }.1
        XCTAssertEqual(row("row_torso_swing",manual)["negativeOperandEvidence"] as? Bool,false)
    }
    func testHistoryReferencesAreActualPrefixAndSeparateMissingValues() {
        let history = [["elbow_min":80.0],["elbow_min":90.0],[:],["elbow_min":20.0]]
        let trace = judge(.pushUp,["front_view_fraction":0,"elbow_min":130],history:history).1
        let op = (row("pushup_shallow",trace)["operands"] as! [[String:Any]])[0]
        XCTAssertEqual((op["referenceEntries"] as! [[String:Any]]).compactMap { $0["index"] as? Int },[0,1,2])
        XCTAssertEqual(op["completeReference"] as? Bool,false)
        XCTAssertEqual(op["positiveOperandEvidence"] as? Bool,false)
    }
    func testSelectorLineageRetainsWholeRepAndSparseReferences() throws {
        let tracker = FormWarningTracker(exercise:.squat)
        var frames = (0..<4).map { FormFrameSample(frame:$0,phase:$0 == 1 ? "bottom" : "rising",side:$0 == 2 ? .right : .left) }
        for i in frames.indices { frames[i].torso = Double(i*10); frames[i].hipY = Double(i); frames[i].shoulderY = Double(i); frames[i].torsoLength = 10 }
        frames[1].knee = 40; frames[2].knee = 80 // unknown knee 0 and 3 remain explicit
        frames[2].heelToe = 0.2; frames[3].heelToe = 0.1
        let aggregation = FormFaultAggregation(frames:frames)
        _ = tracker.metrics2D(frames,isFirstRep:true,evidence:aggregation)
        let rise = try XCTUnwrap(aggregation.metrics["hips_first_torso_rise"])
        let stage = (rise["selectionStages"] as! [[String:Any]])[0]
        XCTAssertEqual(stage["scopeFrames"] as? [Int],[0,1,2,3])
        XCTAssertEqual(stage["selectedFrames"] as? [Int],[1])
        XCTAssertEqual(rise["scopeFrames"] as? [Int],[1,2,3])
        XCTAssertEqual(rise["contributingFrames"] as? [Int],[1,2,3])
        XCTAssertEqual(aggregation.metrics["heel_rise_max"]?["referenceFrames"] as? [Int],[2])
        XCTAssertEqual(aggregation.metrics["heel_rise_max"]?["selectedFrames"] as? [Int],[3])
    }
    func testCoverageCountsIdentityFlushFailuresAndUnknownScope() {
        var records = [[String:Any]]()
        let evidence = FormFaultEvidence(runID:"run",expectedSources:[source(0),source(1)]) { records.append($0) }
        evidence.frame(["observation":"observed"],source:source(0))
        evidence.frame(["observation":"observed"],source:source(1,flush:true))
        evidence.finish(reason:"drained",sourceDrained:true)
        XCTAssertEqual(records.last?["sourceCoverageComplete"] as? Bool,true) // flush is delivery provenance
        XCTAssertEqual(records.last?["frameRecordsWritten"] as? Int,2)
        var bad = [[String:Any]]()
        let failed = FormFaultEvidence(runID:"failed",expectedSources:[source(0)]) { bad.append($0) }
        failed.ingressFailure(source:source(0),reason:"decode_failed"); failed.finish(reason:"drained",sourceDrained:true)
        XCTAssertEqual(bad.last?["sourceCoverageComplete"] as? Bool,false)
        XCTAssertEqual(bad.last?["frameRecordsWritten"] as? Int,0)
        XCTAssertEqual(bad.last?["failedSourcesCount"] as? Int,1)
        var observed = [[String:Any]]()
        let noManifest = FormFaultEvidence(runID:"observed") { observed.append($0) }
        noManifest.frame([:],source:source(0)); noManifest.finish(reason:"drained",sourceDrained:true)
        XCTAssertEqual(observed.last?["writerComplete"] as? Bool,true)
        XCTAssertEqual(observed.last?["sourceCoverageComplete"] as? Bool,false)
    }
    func testFailedObservationAndWrongProcessingFrameCannotCompleteCoverage() {
        for bad in [false,true] {
            var records = [[String:Any]]()
            let writer = FormFaultEvidence(runID:"bad",expectedSources:[source(0)]) { records.append($0) }
            let actual = bad ? FormFaultSource(frame:99,sourceIndex:0,timeValue:0,timeScale:50,session:"fixture",kind:"retained_fixture",flush:false) : source(0)
            writer.frame(["observation":bad ? "observed" : "invalid_coco17_count"],source:actual)
            writer.finish(reason:"drained",sourceDrained:true)
            XCTAssertEqual(records.last?["sourceCoverageComplete"] as? Bool,false)
        }
    }
    func testExactlyTwentyLegacyRulesAndUnknownViewRemainExplicit() {
        let counts = [FormExercise.pushUp,.squat,.barbellRow].map { exercise in
            (judge(exercise,[:]).1["rules"] as! [[String:Any]]).count
        }
        XCTAssertEqual(counts,[8,7,5])
        let result = judge(.pushUp,["hip_dev_max":0]).1
        XCTAssertEqual((result["view"] as! [String:Any])["qualified"] as? Bool,false)
        XCTAssertEqual(row("pushup_hip_sag",result)["callState"] as? String,"false")
    }
    func testBoundedCaptureAndWriteFailureCannotComplete() throws {
        var records = [[String:Any]]()
        let capped = FormFaultEvidence(runID:"cap",maximumRecords:3,maximumBytes:4096) { records.append($0) }
        for i in 0..<10 { capped.frame([:],source:source(i)) }
        capped.finish(reason:"drained",sourceDrained:true)
        XCTAssertEqual(records.last?["failure"] as? String,"capture_limit")
        XCTAssertEqual(records.last?["writerComplete"] as? Bool,false)
        XCTAssertLessThanOrEqual(try records.reduce(0) { $0 + (try JSONSerialization.data(withJSONObject:$1,options:.sortedKeys)).count + 1 },4096)
        struct Failure: Error {}
        var written = [[String:Any]]()
        let failing = FormFaultEvidence(runID:"failure") { record in
            if record["type"] as? String == "frame" { throw Failure() }; written.append(record)
        }
        failing.frame([:],source:source(0)); failing.finish(reason:"drained",sourceDrained:true)
        XCTAssertEqual(written.last?["writerComplete"] as? Bool,false)
        XCTAssertEqual(written.last?["frameRecordsAttempted"] as? Int,1)
        XCTAssertEqual(written.last?["frameRecordsWritten"] as? Int,0)
    }
    func testResetKeepsUniqueTraceIDsAndSeparateHistory() {
        var records = [[String:Any]]()
        let writer = FormFaultEvidence(runID:"same_writer") { records.append($0) }
        let tracker = FormWarningTracker(exercise:.pushUp); tracker.faultEvidence = writer
        for i in 0..<2 {
            tracker.observe(frameIndex:i,coco17:pose(0),phase:"bottom")
            tracker.beginRep(); tracker.finishRep(repIndex:1)
            tracker.reset()
        }
        let replacement = FormWarningTracker(exercise:.pushUp); replacement.faultEvidence = writer
        replacement.observe(frameIndex:2,coco17:pose(0),phase:"bottom"); replacement.beginRep(); replacement.finishRep(repIndex:1)
        writer.finish(reason:"done",sourceDrained:false)
        let reps = records.filter { $0["type"] as? String == "rep" }
        XCTAssertEqual(reps.count,3)
        XCTAssertEqual(Set(reps.compactMap { $0["traceID"] as? String }).count,3)
        XCTAssertNotEqual(reps[0]["traceID"] as? String,reps[1]["traceID"] as? String)
        let second = (reps[1]["judgements"] as! [String:Any])["2d"] as! [String:Any]
        XCTAssertEqual((second["history"] as! [[String:Any]]).count,0)
    }
    func testMissingSelected3DDoesNotBorrowComparison2DAndPhaseIsActual() {
        var records = [[String:Any]]()
        let writer = FormFaultEvidence(runID:"no_3d") { records.append($0) }
        let tracker = FormWarningTracker(exercise:.pushUp); tracker.common.form3DRequired = true
        tracker.faultEvidence = writer
        tracker.observe(frameIndex:0,coco17:pose(20),phase:"caller_actual_phase")
        tracker.beginRep(); let report = tracker.finishRep(repIndex:1)
        writer.finish(reason:"done",sourceDrained:false)
        XCTAssertEqual(report.formSource,"3d_unavailable")
        let frame = records.first { $0["type"] as? String == "frame" }!
        XCTAssertEqual((frame["sample2D"] as! [String:Any])["phase"] as? String,"caller_actual_phase")
        XCTAssertTrue(frame["sample3D"] is NSNull)
        let rep = records.first { $0["type"] as? String == "rep" }!
        XCTAssertTrue((rep["judgements"] as! [String:Any])["3d"] is NSNull)
        XCTAssertNotNil((rep["judgements"] as! [String:Any])["2d"] as? [String:Any])
    }
    func testFacingTraceRecordsActualBranchAndRetainsNonfiniteEvidence() {
        var records = [[String:Any]]()
        let writer = FormFaultEvidence(runID:"facing") { records.append($0) }
        let tracker = FormWarningTracker(exercise:.pushUp); tracker.faultEvidence = writer
        tracker.observe(frameIndex:0,coco17:pose(0),phase:"top")
        var infinite = pose(0); infinite[0].x = .infinity
        tracker.observe(frameIndex:1,coco17:infinite,phase:"top")
        var missing = pose(0); missing[0].confidence = 0
        tracker.observe(frameIndex:2,coco17:missing,phase:"top")
        let frames = records.filter { $0["type"] as? String == "frame" }.map { $0["sample2D"] as! [String:Any] }
        let first = frames[0]["inputSupport"] as! [String:Any]
        XCTAssertEqual((first["facingObservation"] as! [String:Any])["updateKind"] as? String,"establish")
        XCTAssertEqual((first["facingObservation"] as! [String:Any])["seen"] as? Double,1)
        let second = frames[1]["inputSupport"] as! [String:Any]
        XCTAssertEqual((second["facingObservation"] as! [String:Any])["updateKind"] as? String,"confirm")
        XCTAssertEqual((second["jointEvidence"] as! [[String:Any]])[0]["finiteCoordinates"] as? Bool,false)
        XCTAssertTrue((frames[2]["inputSupport"] as! [String:Any])["facingObservation"] is NSNull)
        writer.finish(reason:"done",sourceDrained:false)
    }
    func testPartial3DKeepsMissingJointEvidenceWithoutFilling() {
        var records = [[String:Any]]()
        let writer = FormFaultEvidence(runID:"partial") { records.append($0) }
        let tracker = FormWarningTracker(exercise:.squat); tracker.faultEvidence = writer
        var joints = [SIMD3<Double>](repeating:.zero,count:17)
        joints[5] = SIMD3(repeating:.nan); joints[2] = SIMD3(repeating:.nan)
        tracker.observe(frameIndex:0,coco17:pose(0),pose3D:joints,pose3DState:.partial3D,phase:"bottom")
        tracker.beginRep(); tracker.finishRep(repIndex:1); writer.finish(reason:"done",sourceDrained:false)
        let frame = records.first { $0["type"] as? String == "frame" }!
        let sample = frame["sample3D"] as! [String:Any]
        XCTAssertNil((sample["measurements"] as! [String:Any])["knee"])
        let inputs = sample["inputSupport"] as! [String:Any]
        let support = inputs["jointEvidence"] as! [[String:Any]]
        XCTAssertEqual(support[5]["finiteCoordinates"] as? Bool,false)
        XCTAssertEqual(sample["state3D"] as? String,"partial_3d")
    }
    func testSerializationFailureAndExclusiveFiles() throws {
        var records = [[String:Any]]()
        let writer = FormFaultEvidence(runID:"bad_json") { records.append($0) }
        writer.frame(["nan":Double.nan],source:source(0))
        XCTAssertEqual(records.last?["failure"] as? String,"capture_write_or_serialization_failed")
        XCTAssertEqual(records.last?["writerComplete"] as? Bool,false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let first = try FormFaultEvidence.file(directory:directory,runID:"same")
        first.finish(reason:"done",sourceDrained:false)
        let bytes = try Data(contentsOf:first.url!)
        let second = try FormFaultEvidence.file(directory:directory,runID:"same")
        second.finish(reason:"done",sourceDrained:false)
        XCTAssertNotEqual(first.url,second.url)
        XCTAssertEqual(try Data(contentsOf:first.url!),bytes)
    }
    private func pose(_ hipDrop: Double) -> [PoseKeypoint] {
        var points = [PoseKeypoint](repeating:.init(x:0,y:0,confidence:0.5),count:17)
        for (i,x,y) in [(0,580.0,395.0),(3,560,390),(5,500,400),(7,450,480),(9,500,560),(11,300,450+hipDrop),(13,200,475),(15,100,500)] {
            points[i] = .init(x:x,y:y,confidence:0.9)
            if i != 0 { points[i+1] = .init(x:x,y:y,confidence:0.6) }
        }
        return points
    }
    /// Contract exercises only: these explicit test thresholds are never runtime defaults or accuracy data.
    func testEmitCoreThreeActualTrackerFixtures() throws {
        for exercise in [FormExercise.pushUp,.squat,.barbellRow] {
            let tracker = FormWarningTracker(exercise:exercise)
            tracker.common.baselineRepCount = 1; tracker.common.trendRepCount = 1
            tracker.pushUp.shallowOverBaselineDegrees = -1
            tracker.pushUp.noLockoutBelowSetMaxDegrees = -1
            tracker.squat.noLockoutBelowSetMaxDegrees = -1
            tracker.squat.shallowOverBaselineDegrees = -1
            tracker.squat.hipsFirstTorsoRiseDegrees = -1
            tracker.squat.heelRiseEnabled = true
            tracker.row.torsoSwingRangeDegrees = -1
            tracker.row.standingUpDegrees = -1
            tracker.row.shortPullBelowBaseline = -1
            tracker.row.shrugEnabled = true
            tracker.row.shrugEarShoulderDrop = -1
            tracker.row.shrugMaxHeadAngleChangeDegrees = 180
            var records = [[String:Any]]()
            let writer = FormFaultEvidence(runID:"fixture_\(exercise.rawValue)",
                binding:["fixture":"synthetic_actual_tracker_with_test_only_thresholds","accuracyClaim":false],
                expectedSources:(0..<16).map { source($0) }) { records.append($0) }
            tracker.faultEvidence = writer
            for rep in 0..<4 {
                for step in 0..<4 {
                    let frame = rep*4+step
                    tracker.faultSource = source(frame)
                    var keypoints = pose(Double(60-step*15+rep*2))
                    // Head missing only at ingress: first available reference is not rep start.
                    if rep == 0 && step == 0 { keypoints[3].confidence = 0; keypoints[4].confidence = 0 }
                    tracker.observe(frameIndex:frame,coco17:keypoints,phase:["descending","bottom","ascending","top"][step])
                    if step == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
                }
                tracker.finishRep(repIndex:rep+1)
            }
            writer.finish(reason:"fixture_drained",sourceDrained:true)
            XCTAssertEqual(records.last?["sourceCoverageComplete"] as? Bool,true)
            XCTAssertEqual(records.filter { $0["type"] as? String == "rep" }.count,4)
            if let base = ProcessInfo.processInfo.environment["BPT_FAULT_TEST_TRACE"] {
                let path = base.replacingOccurrences(of:".jsonl",with:"-\(exercise.rawValue).jsonl")
                var data = Data(); for record in records { data += try JSONSerialization.data(withJSONObject:record,options:.sortedKeys); data.append(10) }
                try data.write(to:URL(fileURLWithPath:path),options:.atomic)
            }
        }
    }
    func testCaptureDoesNotChangeReportsOrEventsAndEmitsActualFixture() throws {
        let plain = FormWarningTracker(exercise:.pushUp), traced = FormWarningTracker(exercise:.pushUp)
        var records = [[String:Any]]()
        let expected = (0..<12).map { source($0) }
        let evidence = FormFaultEvidence(runID:"fixture",binding:["fixture":"synthetic_not_accuracy_data"],expectedSources:expected) { records.append($0) }
        traced.faultEvidence = evidence
        for rep in 0..<4 {
            for step in 0..<3 {
                let frame = rep*3+step
                for tracker in [plain,traced] {
                    tracker.faultSource = tracker === traced ? source(frame) : nil
                    tracker.observe(frameIndex:frame,coco17:pose(Double(rep*5)),phase:["descending","bottom","rising"][step])
                    if step == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
                }
            }
            let a = plain.finishRep(repIndex:rep+1), b = traced.finishRep(repIndex:rep+1)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject:a.dictionary,options:.sortedKeys),
                           try JSONSerialization.data(withJSONObject:b.dictionary,options:.sortedKeys))
            XCTAssertEqual(plain.drainEvents(),traced.drainEvents())
        }
        evidence.finish(reason:"fixture_drained",sourceDrained:true)
        XCTAssertEqual(records.last?["sourceCoverageComplete"] as? Bool,true)
        let path = ProcessInfo.processInfo.environment["BPT_FAULT_TEST_TRACE"]
        if let path {
            var data = Data(); for record in records { data += try JSONSerialization.data(withJSONObject:record,options:.sortedKeys); data.append(10) }
            try data.write(to:URL(fileURLWithPath:path),options:.atomic)
        }
    }
}
