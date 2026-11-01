import XCTest
@testable import CalibrationEngineKit

final class TerminalEvidenceTests: XCTestCase {
    func testCaptureFlushRejectsNewInputAndStaleCompletionCannotCloseNewSet() {
        let capture = TerminalEvidenceCapture()
        XCTAssertNil(capture.snapshot())
        let first = capture.begin()
        XCTAssertEqual(capture.snapshot(), first)
        XCTAssertEqual(capture.beginFlush(), first)
        XCTAssertNil(capture.snapshot()) // new capture cannot enter a closing set
        XCTAssertTrue(capture.accepts(first)) // already captured lookahead tail can finish
        let second = capture.begin()
        XCTAssertFalse(capture.accepts(first))
        XCTAssertFalse(capture.finish(first)) // old endSet callback cannot close second
        XCTAssertEqual(capture.snapshot(), second)
        XCTAssertTrue(capture.accepts(second))
        XCTAssertTrue(capture.finish(second))
        XCTAssertFalse(capture.accepts(second))
        XCTAssertNil(capture.snapshot())
    }

    func testBudgetIsBoundedBeforeAsyncEnqueueAndCapCannotResume() {
        var budget = TerminalEvidenceBudget(maximumBytes: 2048, maximumRecords: 2)
        XCTAssertTrue(budget.admit(400))
        XCTAssertTrue(budget.admit(400))
        XCTAssertFalse(budget.admit(1))
        XCTAssertTrue(budget.capped)
        XCTAssertEqual(budget.bytes, 800)
        XCTAssertEqual(budget.records, 2)
        XCTAssertFalse(budget.admit(1))
        var size = TerminalEvidenceBudget(maximumBytes: 2048, maximumRecords: 20)
        XCTAssertFalse(size.admit(1025)) //1024 reserved for the explicit incomplete marker
        XCTAssertEqual(size.bytes, 0)
        var malformed = TerminalEvidenceBudget()
        XCTAssertFalse(malformed.admit(-1))
    }

    func testStrictJSONNeverSerializesNaNAsGeometry() throws {
        let row = ["raw": TerminalEvidence.vector([1, .nan, .infinity]), "missing": TerminalEvidence.number(nil)]
        let encoded = try JSONSerialization.data(withJSONObject: row)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let values = try XCTUnwrap(parsed["raw"] as? [Any])
        XCTAssertEqual(values[0] as? Double, 1)
        XCTAssertTrue(values[1] is NSNull)
        XCTAssertTrue(values[2] is NSNull)
        XCTAssertTrue(parsed["missing"] is NSNull)
    }

    func testDiagnosticAngleProtocolMatchesNativeJointDefinition() throws {
        XCTAssertEqual(FormGeometry.h36mSide(.left).elbow, 12)
        XCTAssertEqual(FormGeometry.h36mSide(.right).elbow, 15)
        XCTAssertEqual(FormGeometry.h36mSide(.left).hip, 4)
        let origin = SIMD3<Double>(0,0,0)
        XCTAssertEqual(try XCTUnwrap(FormGeometry.angle3D(SIMD3(1,0,0), origin, SIMD3(0,1,0))), 90, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(FormGeometry.angle3D(SIMD3(1,0,0), origin, SIMD3(-sqrt(3)/2,0.5,0))), 150, accuracy: 1e-10)
    }
    func testFailedIOOrSerializationCannotWriteACompletedFooter() throws {
        var writes = 0
        let broken = TerminalEvidenceStream { _ in
            writes += 1
            throw CocoaError(.fileWriteOutOfSpace)
        }
        broken.append("terminal_frame", ["frame": 1])
        broken.append("terminal_end", ["incomplete": false])
        broken.drain()
        XCTAssertEqual(writes, 1)
        var rows: [Data] = []
        let malformed = TerminalEvidenceStream { rows.append($0) }
        malformed.append("terminal_header", [:])
        malformed.append("terminal_frame", ["score": Double.nan])
        malformed.append("terminal_end", ["incomplete": false])
        malformed.drain()
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(String(decoding: rows[0], as: UTF8.self).contains("terminal_end"))
    }

    func testActualEncodedStreamSequencesAndExplicitCap() throws {
        var rows: [Data] = []
        let stream = TerminalEvidenceStream(maximumRecords: 2) { rows.append($0) }
        stream.append("terminal_header", [:])
        stream.append("terminal_frame", ["frame": 1])
        stream.append("terminal_end", ["incomplete": false])
        stream.append("terminal_end", ["incomplete": false])
        stream.drain()
        let parsed = try rows.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
        XCTAssertEqual(parsed.compactMap { $0["sequence"] as? Int }, [0,1,2])
        XCTAssertEqual(parsed.last?["type"] as? String, "terminal_capped")
        XCTAssertEqual(parsed.last?["incomplete"] as? Bool, true)
    }

    func testActualTrackerExposesUnfinishedBoundaryWithoutFinishingARep() {
        let tracker = FormWarningTracker(exercise: .pushUp)
        let points = [PoseKeypoint](repeating: .init(x: 10, y: 10, confidence: 0.8), count: 17)
        tracker.observe(frameIndex: 10, coco17: points, phase: "lowering")
        XCTAssertNil(tracker.diagnosticActiveRepStart)
        tracker.beginRep()
        XCTAssertEqual(tracker.diagnosticActiveRepStart, 10)
        tracker.observe(frameIndex: 11, coco17: points, phase: "bottom")
        tracker.recordCurrentFrame()
        XCTAssertEqual(tracker.diagnosticActiveRepStart, 10)
        XCTAssertTrue(tracker.reports.isEmpty)
        tracker.finishRep(repIndex: 1)
        XCTAssertNil(tracker.diagnosticActiveRepStart)
        tracker.observe(frameIndex: 20, coco17: points, phase: "lowering")
        tracker.beginRep()
        XCTAssertEqual(tracker.diagnosticActiveRepStart, 20)
        XCTAssertEqual(tracker.reports.count, 1) // no completed second report exists
    }

    func testImplicitLifterFlushAlsoMarksOldClampedOutputs() throws {
        var live = MotionAGFormerLive<Int>(lookahead: 5, cadence: 1, predict: { _ in Array(repeating: 0, count: 27*17*3) })
        let points = [PoseKeypoint](repeating: .init(x: 100, y: 100, confidence: 0.8), count: 17)
        for i in 0..<10 {
            let emitted = try live.push(frameIndex: i, coco17: points, imageWidth: 640, imageHeight: 480, payload: i)
            XCTAssertTrue(emitted.allSatisfy { !$0.1.diagnosticFlushed })
        }
        let changed = try live.push(frameIndex: 10, coco17: points, imageWidth: 640, imageHeight: 480,
                                    captureRotation: .cw90, payload: 10)
        XCTAssertFalse(changed.isEmpty)
        XCTAssertTrue(changed.allSatisfy { $0.1.diagnosticFlushed })
        XCTAssertEqual(changed.map { $0.0 }, [5,6,7,8,9])
    }

    func testAlreadyCapturedPayloadDrainCannotBeClosedByFlushOrStaleCallbacks() throws {
        let capture = TerminalEvidenceCapture()
        let first = capture.begin()
        XCTAssertEqual(capture.capture(frame: 10), first)
        XCTAssertEqual(capture.capture(frame: 11), first)
        XCTAssertEqual(capture.beginFlush(), first)
        XCTAssertNil(capture.capture(frame: 12)) // no new post-end sources join the closing lease
        XCTAssertEqual(capture.drainStatus(first)?.pending, 2)
        capture.delivered(epoch: first, frame: 11) // clamped tail delivered first
        XCTAssertEqual(capture.drainStatus(first)?.pending, 1) // genuine older nonflush is still pending
        capture.delivered(epoch: first, frame: 11) // duplicate cannot release somebody else's payload
        XCTAssertEqual(capture.drainStatus(first)?.pending, 1)
        capture.delivered(epoch: first, frame: 10)
        XCTAssertEqual(capture.drainStatus(first)?.pending, 0)
        let next = capture.begin()
        XCTAssertEqual(capture.capture(frame: 10), next)
        capture.delivered(epoch: first, frame: 10)
        XCTAssertEqual(capture.drainStatus(next)?.pending, 1)
        XCTAssertFalse(capture.finish(first))
        capture.delivered(epoch: next, frame: 10, failed: true)
        XCTAssertEqual(capture.drainStatus(next)?.pending, 0)
        XCTAssertEqual(capture.drainStatus(next)?.failed, true)
    }

    func testEOFFenceAdmitsAlreadyAcceptedProcessingBeforeClosingEpoch() {
        let queue = DispatchQueue(label: "terminal-ingress-fence-test")
        let accepted = DispatchSemaphore(value: 0)
        let completed = expectation(description: "EOF barrier after last accepted frame")
        let capture = TerminalEvidenceCapture()
        let epoch = capture.begin()
        queue.async {
            accepted.wait()
            XCTAssertEqual(capture.capture(frame: 999), epoch)
        }
        TerminalEvidenceIngressFence.afterPending(on: queue) {
            XCTAssertEqual(capture.drainStatus(epoch)?.pending, 1)
            XCTAssertEqual(capture.beginFlush(), epoch)
            XCTAssertNil(capture.capture(frame: 1000))
            capture.delivered(epoch: epoch, frame: 999)
            XCTAssertEqual(capture.drainStatus(epoch)?.pending, 0)
            completed.fulfill()
        }
        XCTAssertEqual(capture.drainStatus(epoch)?.pending, 0)
        accepted.signal()
        wait(for: [completed], timeout: 2)
    }

}
