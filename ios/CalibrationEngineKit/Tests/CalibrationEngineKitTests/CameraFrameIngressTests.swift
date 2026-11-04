import XCTest
@testable import CalibrationEngineKit

final class CameraFrameIngressTests: XCTestCase {
    func testNewCameraFrameZeroCannotInheritOldClipIndex() {
        let first = CameraIngressBinding(generation:"camera-A",faultRunID:"capture-A")
        let old = first.frame(processingFrame:0,source:.init(sourceID:"old-clip",sourceIndex:417))
        let second = CameraIngressBinding(generation:"camera-B",faultRunID:"capture-B")
        let fresh = second.frame(processingFrame:0,source:nil)
        XCTAssertEqual(old.sourceIndex,417)
        XCTAssertEqual(fresh.sourceIndex,0)
        XCTAssertNotEqual(fresh.sourceID,old.sourceID)
        XCTAssertEqual(fresh.faultRunID,"capture-B")
    }

    func testQueuedCallbackRetainsOriginalBindingAfterHandlerReplacement() throws {
        let route = CameraIngressRoute<(Int,CameraSourceFrame?) -> CameraFrameIngress>()
        let first = CameraIngressBinding(generation:"A",faultRunID:"run-A")
        route.install { first.frame(processingFrame:$0,source:$1) }
        // Camera manager snapshots this before enqueuing; source can arrive before any log append.
        let queued = try XCTUnwrap(route.snapshot())
        let second = CameraIngressBinding(generation:"B",faultRunID:"run-B")
        route.install { second.frame(processingFrame:$0,source:$1) }
        let source = CameraSourceFrame(sourceID:"clip-A",sourceIndex:51)
        let delivered = queued(0,source)
        XCTAssertEqual(delivered.generation,"A")
        XCTAssertEqual(delivered.faultRunID,"run-A")
        XCTAssertEqual(delivered.sourceIndex,51)
        XCTAssertEqual(try XCTUnwrap(route.snapshot())(0,nil).generation,"B")
    }

    func testOldFeederAndDelayedLiftCannotUpdateNewConsumer() {
        let gate = CameraIngressGeneration()
        let a = CameraIngressBinding(generation:"A",faultRunID:"run-A")
        let b = CameraIngressBinding(generation:"B",faultRunID:"run-B")
        let queuedA = a.frame(processingFrame:0,source:.init(sourceID:"clip-A",sourceIndex:90))
        gate.activate("A")
        XCTAssertTrue(gate.accepts(queuedA))
        // A remains immutable after B becomes current; both pre-inference and delayed-output gates reject A.
        gate.activate("B")
        var consumed = [CameraFrameIngress]()
        for frame in [queuedA,b.frame(processingFrame:0,source:.init(sourceID:"clip-B",sourceIndex:7)),queuedA] {
            if gate.accepts(frame) { consumed.append(frame) }
        }
        XCTAssertEqual(consumed.count,1)
        XCTAssertEqual(consumed.first?.sourceIndex,7)
        XCTAssertEqual(queuedA.faultRunID,"run-A")
        gate.activate(nil)
        XCTAssertFalse(gate.accepts(consumed.first))
    }

    func testSameClipFrameAcrossOccurrencesHasDistinctIdentity() {
        let binding = CameraIngressBinding(generation:"camera",faultRunID:"run")
        let first = binding.frame(processingFrame:0,source:.init(sourceID:"clip-loop-0",sourceIndex:0))
        let second = binding.frame(processingFrame:99,source:.init(sourceID:"clip-loop-1",sourceIndex:0))
        XCTAssertEqual(first.sourceIndex,second.sourceIndex)
        XCTAssertNotEqual(first.sourceID,second.sourceID)
        XCTAssertEqual(first.generation,second.generation)
    }

    func testStopPreservesCurrentDrainButNewSetupRejectsOldFlush() {
        let gate = CameraIngressGeneration()
        let a = CameraIngressBinding(generation:"A",faultRunID:"run-A").frame(processingFrame:4,source:nil)
        gate.activate("A")
        XCTAssertTrue(gate.acceptsIngress(a))
        gate.stopIngress()
        XCTAssertFalse(gate.acceptsIngress(a))
        XCTAssertTrue(gate.accepts(a)) // an already-computed current-session tail may still be delivered
        gate.activate("B")
        XCTAssertFalse(gate.accepts(a)) // never deliver old flush into the replacement tracker
        XCTAssertFalse(gate.acceptsIngress(a))
    }

    func testOldCameraOutputRouteIsRemovedRatherThanRelabelled() throws {
        let routes = CameraIngressRoute<[String:CameraIngressBinding]>()
        routes.install(["output-A":CameraIngressBinding(generation:"A",faultRunID:"run-A")])
        routes.install(["output-B":CameraIngressBinding(generation:"B",faultRunID:"run-B")])
        let snapshot = try XCTUnwrap(routes.snapshot())
        XCTAssertNil(snapshot["output-A"])
        XCTAssertEqual(snapshot["output-B"]?.generation,"B")
    }

    func testUnboundIdentityStaysUnboundAndMissingDelayedIdentityRejected() {
        let binding = CameraIngressBinding(generation:"camera",faultRunID:nil)
        let frame = binding.frame(processingFrame:5,source:nil)
        XCTAssertNil(frame.faultRunID)
        let gate = CameraIngressGeneration(); gate.activate("camera")
        XCTAssertTrue(gate.accepts(frame))
        XCTAssertFalse(gate.accepts(nil))
    }
}
