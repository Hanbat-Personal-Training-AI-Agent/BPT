import XCTest
@testable import CalibrationEngineKit

final class PushUpSupportCorridor2DTests: XCTestCase {
    typealias Guard = PushUpSupportCorridor2D
    let origin = Guard.Point(x: 100, y: 200)
    func observation(_ p: Guard.Point? = nil, reliable: Bool = true, confidence: Double = 0.95) -> Guard.Observation {
        .init(point: p ?? origin, confidence: confidence, reliablyObserved: reliable, neighborEvidenceConsistent: true, temporalEvidenceConsistent: true)
    }
    func input(_ t: Double, _ p: Guard.Point? = nil, reliable: Bool = true) -> Guard.Input {
        .init(sourcePTS: t, context: .init(session: "s", camera: "c", tracker: "t", person: "p", fixedCamera: true),
              isPushUp: true, supportActive: true, bodyScale: 200,
              left: observation(p, reliable: reliable, confidence: reliable ? 0.95 : 0.1), right: observation())
    }
    func enabled() -> Guard { var c = Guard.Config(); c.enabled = true; return Guard(config: c) }
    func acquire(_ guardValue: inout Guard) {
        for t in [0.0, 0.07, 0.14] { _ = guardValue.update(input(t)) }
    }
    func testDefaultOffPreservesRaw() {
        var g = Guard(); let i = input(0, .init(x: 999, y: 5), reliable: false)
        let r = g.update(i)
        XCTAssertEqual(r.left.displayPoint, i.left.point); XCTAssertEqual(r.left.reason, .disabled)
        XCTAssertEqual(r.left.raw.point, i.left.point); XCTAssertFalse(r.left.assessmentEligible)
    }
    func testStableAcquisitionRequiresDurationAndObservation() {
        var g = enabled()
        for t in [0.0, 0.001, 0.002] { XCTAssertNil(g.update(input(t)).left.anchor) }
        XCTAssertEqual(g.update(input(0.14)).left.anchor, origin)
        var h = enabled()
        for t in [0.0, 0.07, 0.14] { XCTAssertNil(h.update(input(t, reliable: false)).left.displayPoint) }
    }
    func testConfidentMovementAndBadPosturePassThroughUnchanged() {
        var g = enabled(); acquire(&g)
        let badPosture = Guard.Point(x: 480, y: -90)
        let r = g.update(input(0.21, badPosture))
        XCTAssertEqual(r.left.displayPoint, badPosture); XCTAssertEqual(r.left.reason, .observedReleased)
        XCTAssertTrue(r.left.assessmentEligible); XCTAssertFalse(r.left.inferred); XCTAssertNil(r.left.anchor)
        XCTAssertEqual(r.left.correctionMagnitude, 0)
    }
    func testLowConfidenceJumpBoundedDoesNotMoveAnchorAndBlocksCoaching() {
        var g = enabled(); acquire(&g)
        let raw = Guard.Point(x: 800, y: 900)
        let r = g.update(input(0.21, raw, reliable: false))
        XCTAssertEqual(r.left.raw.point, raw); XCTAssertEqual(r.left.anchor, origin)
        XCTAssertLessThanOrEqual(r.left.displayPoint!.distance(to: origin), 12.000001)
        XCTAssertGreaterThan(r.left.correctionMagnitude!, 900)
        XCTAssertTrue(r.left.inferred); XCTAssertFalse(r.left.assessmentEligible)
        XCTAssertFalse(r.left.armAndHandCoachingEligible)
        XCTAssertEqual(r.left.occlusionAge!, 0.07, accuracy: 1e-8)
    }
    func testCoherentObservedRelocationReacquiresAtNewSupport() {
        var g = enabled(); acquire(&g)
        let moved = Guard.Point(x: 150, y: 250)
        XCTAssertEqual(g.update(input(0.21, moved)).left.reason, .observedReleased)
        _ = g.update(input(0.28, moved)); let r = g.update(input(0.35, moved))
        XCTAssertEqual(r.left.anchor, moved)
        XCTAssertEqual(g.update(input(0.42, reliable: false)).left.anchor, moved)
    }
    func testHiddenRealMovementIsUnknowableAndExpiresInsteadOfClaimingSuccess() {
        var g = enabled(); acquire(&g)
        var last: Guard.Result?
        for t in [0.21, 0.28, 0.35, 0.42, 0.49, 0.56] {
            last = g.update(input(t, .init(x: 800, y: 900), reliable: false))
            XCTAssertFalse(last!.left.assessmentEligible)
        }
        XCTAssertNil(last!.left.displayPoint); XCTAssertTrue(last!.withholdSkeleton)
        XCTAssertEqual(last!.left.reason, .occlusionExpired)
        XCTAssertNil(g.update(input(0.63, reliable: false)).left.anchor)
    }
    func testNoObservationCannotFabricateRelocation() {
        var g = enabled(); acquire(&g)
        for t in [0.21, 0.28, 0.35] {
            let r = g.update(input(t, .init(x: 150, y: 250), reliable: false))
            XCTAssertEqual(r.left.anchor, origin)
        }
    }
    func testMissingAndNaNWristsNeverEmitNaNOrClaimObserved() {
        var g = enabled(); acquire(&g)
        var i = input(0.21); i.left = .init(point: nil, confidence: 0, reliablyObserved: false, neighborEvidenceConsistent: false, temporalEvidenceConsistent: false)
        let missing = g.update(i)
        XCTAssertEqual(missing.left.displayPoint, origin); XCTAssertNil(missing.left.correctionMagnitude)
        i.sourcePTS = 0.28; i.left = observation(.init(x: .nan, y: 0))
        let nan = g.update(i)
        XCTAssertEqual(nan.left.displayPoint, origin); XCTAssertFalse(nan.left.assessmentEligible)
    }
    func testCameraMotionAndEveryIdentityChangeResetAnchor() {
        for key in ["camera", "tracker", "person", "session", "stability"] {
            var g = enabled(); acquire(&g); var i = input(0.21, reliable: false)
            switch key {
            case "camera": i.context.camera = "new"
            case "tracker": i.context.tracker = "new"
            case "person": i.context.person = "new"
            case "session": i.context.session = "new"
            default: i.context.fixedCamera = false
            }
            let r = g.update(i); XCTAssertNil(r.left.anchor, key); XCTAssertNil(r.left.displayPoint, key)
        }
    }
    func testExplicitResetAndInactiveExerciseClearMemory() {
        var g = enabled(); acquire(&g); g.reset()
        XCTAssertNil(g.update(input(0.21, reliable: false)).left.anchor)
        for active in [true, false] {
            acquire(&g); var i = input(0.21, reliable: false)
            i.isPushUp = active; i.supportActive = !active
            XCTAssertNil(g.update(i).left.displayPoint)
        }
    }
    func testTimeReversalDuplicateAndLongGapCannotUsePreviousAnchor() {
        for t in [0.1, 0.14, 1.0, Double.nan] {
            var g = enabled(); acquire(&g)
            let r = g.update(input(t, reliable: false))
            XCTAssertNil(r.left.displayPoint); XCTAssertNil(r.left.anchor)
        }
    }
    func testInvalidConfigurationAndScaleFailClosed() {
        var configs: [Guard.Config] = []
        var c = Guard.Config(); c.enabled = true; c.reliableConfidence = .nan; configs.append(c)
        c = Guard.Config(); c.enabled = true; c.minimumSamples = 0; configs.append(c)
        c = Guard.Config(); c.enabled = true; c.maximumOcclusionSeconds = .infinity; configs.append(c)
        for config in configs {
            var g = Guard(config: config)
            XCTAssertNil(g.update(input(0, reliable: false)).left.displayPoint)
        }
        var timestampGuard = enabled(); var invalidTime = input(.nan)
        XCTAssertFalse(timestampGuard.update(invalidTime).left.assessmentEligible)
        invalidTime.sourcePTS = .infinity
        XCTAssertFalse(timestampGuard.update(invalidTime).left.armAndHandCoachingEligible)
        for scale in [0.0, -1, .nan, .infinity] {
            var g = enabled(); acquire(&g); var i = input(0.21, reliable: false); i.bodyScale = scale
            XCTAssertNil(g.update(i).left.displayPoint)
        }
    }
    func testBodyMotionDoesNotFreezeObservedWristOrIntroduceRoot3D() {
        var g = enabled(); acquire(&g)
        // Root/body translation is absent from this API: only actual camera wrist observations enter it.
        for (t, x) in [(0.21, 120.0), (0.28, 140.0), (0.35, 160.0)] {
            let p = Guard.Point(x: x, y: 200), r = g.update(input(t, p))
            XCTAssertEqual(r.left.displayPoint, p); XCTAssertFalse(r.left.inferred)
        }
    }
    func testBodyScaleChangesDoNotEnlargeExistingCorridor() {
        var g = enabled(); acquire(&g); var i = input(0.21, .init(x: 800, y: 900), reliable: false)
        i.bodyScale = 2000
        XCTAssertLessThanOrEqual(g.update(i).left.displayPoint!.distance(to: origin), 12.000001)
    }
    func testNeighborAndTemporalEvidenceAreIndependentVetoes() {
        for neighbor in [true, false] {
            var g = enabled(); acquire(&g); var i = input(0.21, .init(x: 800, y: 900))
            i.left.neighborEvidenceConsistent = neighbor
            i.left.temporalEvidenceConsistent = !neighbor
            let r = g.update(i)
            XCTAssertEqual(r.left.anchor, origin); XCTAssertTrue(r.left.inferred)
            XCTAssertFalse(r.left.armAndHandCoachingEligible)
        }
    }
    func testHighConfidenceWithoutReliableVisibilityCannotRelease() {
        var g = enabled(); acquire(&g); var i = input(0.21)
        i.left = observation(.init(x: 800, y: 900), reliable: false, confidence: 0.99)
        let r = g.update(i); XCTAssertEqual(r.left.anchor, origin); XCTAssertTrue(r.left.inferred)
    }
}
