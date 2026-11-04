import XCTest
@testable import CalibrationEngineKit

final class ExerciseMotionObserverLogTests: XCTestCase {
    private var directory: URL!
    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }
    private func records(_ url: URL) throws -> [[String: Any]] {
        try Data(contentsOf: url).split(separator: 10).map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
        }
    }
    private func footer(_ url: URL) throws -> [String: Any] {
        let rows = try records(url)
        XCTAssertEqual(rows.filter { $0["type"] as? String == "footer" }.count, 1)
        let last = try XCTUnwrap(rows.last)
        XCTAssertEqual(last["type"] as? String, "footer")
        return last
    }
    func testNormalDrainFooterPreservesHeaderAndCountsAndIsFinal() throws {
        let log = try ExerciseMotionObserverLog(directory: directory)
        log.write(["schema": "bpt.motion-observer.v1", "source": ["frame": 10]])
        log.write(["type": "account_profile_binding"])
        log.recordSuppressed(.flushTail)
        log.recordSuppressed(.noRawModelOutput)
        log.finish(drained: true)
        let original = try Data(contentsOf: log.url)
        log.write(["late": true]); log.recordSuppressed(.stoppedGeneration)
        log.finish(drained: false); log.close()
        XCTAssertEqual(try Data(contentsOf: log.url), original)
        let header = try XCTUnwrap(records(log.url).first)
        XCTAssertEqual(header["schema"] as? String, "bpt.motion-observer-log.v1")
        XCTAssertEqual(header["completion_requires_footer"] as? Bool, true)
        let end = try footer(log.url)
        XCTAssertEqual(end["complete"] as? Bool, true)
        XCTAssertEqual(end["reason"] as? String, "normal_drain")
        XCTAssertEqual(end["data_rows_attempted"] as? Int, 2)
        XCTAssertEqual(end["data_rows_written"] as? Int, 2)
        XCTAssertEqual(end["observation_rows_written"] as? Int, 1)
        XCTAssertEqual(end["data_rows_rejected"] as? Int, 0)
        XCTAssertEqual(end["suppressed_outputs"] as? [String: Int],
                       ["flush_tail_not_fresh_observation": 1, "no_raw_model_output": 1])
        XCTAssertEqual(end["bytes_before_footer"] as? Int,
                       original.split(separator: 10).dropLast().reduce(0) { $0 + $1.count + 1 })
    }
    func testRowCapReservesFooterAndRunsNeverOverwrite() throws {
        let a = try ExerciseMotionObserverLog(directory: directory, maximumRows: 3)
        a.write(["test": 1]); a.write(["test": 2]); a.finish(drained: true)
        let before = try Data(contentsOf: a.url)
        let end = try footer(a.url)
        XCTAssertEqual(try records(a.url).count, 3)
        XCTAssertEqual(end["complete"] as? Bool, false)
        XCTAssertEqual(end["reason"] as? String, "row_limit")
        XCTAssertEqual(end["data_rows_rejected"] as? Int, 1)
        XCTAssertEqual(end["data_rows_written"] as? Int, 1)
        let b = try ExerciseMotionObserverLog(directory: directory, maximumRows: 2)
        b.finish(drained: true)
        XCTAssertNotEqual(a.url, b.url)
        XCTAssertEqual(try Data(contentsOf: a.url), before)
        XCTAssertEqual(try records(b.url).count, 2)
    }
    func testByteCapAndOversizeRecordEndIncompleteWithinBounds() throws {
        let a = try ExerciseMotionObserverLog(directory: directory, maximumBytes: 4096)
        a.write(["payload": String(repeating: "x", count: 3000)])
        XCTAssertEqual(try footer(a.url)["reason"] as? String, "byte_limit")
        XCTAssertLessThanOrEqual(try Data(contentsOf: a.url).count, 4096)
        let b = try ExerciseMotionObserverLog(directory: directory)
        b.write(["payload": String(repeating: "x", count: 24_577)])
        XCTAssertEqual(try footer(b.url)["reason"] as? String, "record_too_large")
        XCTAssertEqual(try records(b.url).count, 2)
    }
    func testInvalidSerializationCannotBeHiddenByNormalFinish() throws {
        for value: [String: Any] in [["not_json": Date()], ["number": Double.nan]] {
            let log = try ExerciseMotionObserverLog(directory: directory)
            log.write(value); log.finish(drained: true)
            let end = try footer(log.url)
            XCTAssertEqual(end["complete"] as? Bool, false)
            XCTAssertEqual(end["reason"] as? String, "serialization_failure")
            XCTAssertEqual(end["data_rows_rejected"] as? Int, 1)
        }
    }
    func testPartialWriteRecoversBoundaryAndReportsFailure() throws {
        var writes = 0
        let log = try ExerciseMotionObserverLog(directory: directory) { handle, data in
            writes += 1
            if writes == 2 {
                try handle.write(contentsOf: Data(data.prefix(4)))
                throw CocoaError(.fileWriteUnknown)
            }
            try handle.write(contentsOf: data)
        }
        log.write(["test": 1]); log.finish(drained: true)
        let end = try footer(log.url)
        XCTAssertEqual(try records(log.url).count, 2)
        XCTAssertEqual(end["reason"] as? String, "write_failure")
        XCTAssertEqual(end["complete"] as? Bool, false)
        XCTAssertEqual(end["data_rows_written"] as? Int, 0)
    }
    func testFooterWriteFailureRemovesAlreadyWrittenSuccessClaim() throws {
        var writes = 0
        let log = try ExerciseMotionObserverLog(directory: directory) { handle, data in
            writes += 1
            try handle.write(contentsOf: data)
            if writes == 2 { throw CocoaError(.fileWriteUnknown) }
        }
        log.finish(drained: true)
        let end = try footer(log.url)
        XCTAssertEqual(end["complete"] as? Bool, false)
        XCTAssertEqual(end["reason"] as? String, "write_failure")
    }
    func testPersistentWriteFailureLeavesNoCompletionClaim() throws {
        var writes = 0
        let log = try ExerciseMotionObserverLog(directory: directory) { handle, data in
            writes += 1
            if writes > 1 { throw CocoaError(.fileWriteOutOfSpace) }
            try handle.write(contentsOf: data)
        }
        log.write(["test": 1]); log.finish(drained: true)
        let rows = try records(log.url)
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows.contains { $0["complete"] as? Bool == true })
        XCTAssertEqual(rows.first?["completion_requires_footer"] as? Bool, true)
    }
    func testInterruptStopDeinitUnconfirmedDrainAndPendingTailStayIncomplete() throws {
        let interrupted = try ExerciseMotionObserverLog(directory: directory)
        interrupted.markIncomplete(.background); interrupted.finish(drained: true)
        XCTAssertEqual(try footer(interrupted.url)["reason"] as? String, "background")
        let stopped = try ExerciseMotionObserverLog(directory: directory)
        stopped.close(reason: .cameraStop); stopped.finish(drained: true)
        XCTAssertEqual(try footer(stopped.url)["reason"] as? String, "camera_stop")
        var abandoned: ExerciseMotionObserverLog? = try ExerciseMotionObserverLog(directory: directory)
        let url = try XCTUnwrap(abandoned?.url); abandoned = nil
        XCTAssertEqual(try footer(url)["reason"] as? String, "deinitialized")
        let unconfirmed = try ExerciseMotionObserverLog(directory: directory)
        unconfirmed.finish(drained: false)
        XCTAssertEqual(try footer(unconfirmed.url)["reason"] as? String, "drain_not_confirmed")
        let tail = try ExerciseMotionObserverLog(directory: directory)
        tail.finish(drained: true, pendingFrames: 5)
        XCTAssertEqual(try footer(tail.url)["reason"] as? String, "unflushed_tail")
        XCTAssertEqual(try footer(tail.url)["pending_frames"] as? Int, 5)
        let fakeNormalClose = try ExerciseMotionObserverLog(directory: directory)
        fakeNormalClose.close(reason: .normalDrain)
        XCTAssertEqual(try footer(fakeNormalClose.url)["complete"] as? Bool, false)
    }
    func testStoppedGenerationSuppressionIsCountedAndPreventsCompletion() throws {
        let log = try ExerciseMotionObserverLog(directory: directory)
        log.recordSuppressed(.stoppedGeneration); log.finish(drained: true)
        let end = try footer(log.url)
        XCTAssertEqual(end["suppressed_outputs"] as? [String: Int], ["stopped_generation": 1])
        XCTAssertEqual(end["reason"] as? String, "stopped_generation")
        XCTAssertEqual(end["complete"] as? Bool, false)
    }
    func testMissingExpectedObservationAndSupersededDrainStayIncomplete() throws {
        let missing = try ExerciseMotionObserverLog(directory: directory)
        missing.recordSuppressed(.unavailable); missing.finish(drained: true)
        XCTAssertEqual(try footer(missing.url)["complete"] as? Bool, false)
        XCTAssertEqual(try footer(missing.url)["reason"] as? String, "missing_observation")
        let superseded = try ExerciseMotionObserverLog(directory: directory)
        superseded.markIncomplete(.drainSuperseded)
        superseded.write(["later_session": true]); superseded.finish(drained: true)
        XCTAssertEqual(try footer(superseded.url)["complete"] as? Bool, false)
        XCTAssertEqual(try footer(superseded.url)["reason"] as? String, "drain_superseded")
        let invalid = try ExerciseMotionObserverLog(directory: directory)
        invalid.finish(drained: true, pendingFrames: -1)
        XCTAssertEqual(try footer(invalid.url)["complete"] as? Bool, false)
        XCTAssertEqual(try footer(invalid.url)["reason"] as? String, "invalid_pending_frames")
        XCTAssertEqual(try footer(invalid.url)["pending_frames"] as? Int, 0)
    }
    func testInvalidLimitsFailBeforeCreatingOutput() throws {
        XCTAssertThrowsError(try ExerciseMotionObserverLog(directory: directory, maximumRows: 1))
        XCTAssertThrowsError(try ExerciseMotionObserverLog(directory: directory, maximumBytes: 2000))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    func testPendingCountDistinguishesUnflushedTailAndNormalFlush() throws {
        var live = MotionAGFormerLive<Int>(lookahead: 5, predict: MotionAGFormerLiveTests.fakePredict)
        let fixture = try MotionAGFormerLiveTests().fixture()
        for i in 0..<35 {
            let values = fixture.coco17[min(i, fixture.coco17.count - 1)]
            let kp = values.map { PoseKeypoint(x: $0[0], y: $0[1], confidence: $0[2]) }
            _ = try live.push(frameIndex: i, coco17: kp,
                              imageWidth: fixture.image_size[0], imageHeight: fixture.image_size[1], payload: i)
        }
        XCTAssertEqual(live.pendingFrameCount, 5)
        let tail = try live.flush()
        XCTAssertEqual(tail.count, 5)
        XCTAssertEqual(live.pendingFrameCount, 0)
        XCTAssertTrue(tail.allSatisfy { $0.1.diagnosticFlushed })
    }
}
