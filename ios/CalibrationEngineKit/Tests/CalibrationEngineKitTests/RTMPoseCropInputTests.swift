import CoreGraphics
import XCTest
@testable import CalibrationEngineKit

final class RTMPoseCropInputTests: XCTestCase {
    /// Standing person: 17 COCO joints in a 200×600 box at (400, 500) in a 1080×1920 frame.
    private func person(dx: Double = 0, dy: Double = 0, confidence: Double = 0.9) -> [PoseKeypoint] {
        (0..<17).map { j in
            PoseKeypoint(x: 400 + dx + Double(j % 3) * 100, y: 500 + dy + Double(j) * 37.5, confidence: confidence)
        }
    }

    func testFitToInputAspectIsThreeByFourAroundTheSameCentre() {
        for rect in [CGRect(x: 10, y: 20, width: 100, height: 600), CGRect(x: 0, y: 0, width: 900, height: 200)] {
            let fitted = RTMPoseCropTracker.fitToInputAspect(rect)
            XCTAssertEqual(fitted.width / fitted.height, 0.75, accuracy: 1e-9)
            XCTAssertTrue(fitted.contains(rect))
            XCTAssertEqual(fitted.midX, rect.midX, accuracy: 1e-9)
            XCTAssertEqual(fitted.midY, rect.midY, accuracy: 1e-9)
        }
    }

    func testCropFollowsPersonWithMarginAndHoldsThroughJitter() throws {
        var tracker = RTMPoseCropTracker()
        XCTAssertEqual(tracker.inputRect(imageWidth: 1080, imageHeight: 1920), CGRect(x: 0, y: 0, width: 1080, height: 1920))
        tracker.update(person())
        let crop = try XCTUnwrap(tracker.crop)
        XCTAssertEqual(crop.width / crop.height, 0.75, accuracy: 1e-9)
        // Every joint inside, with room above the eyes and below the ankles.
        for p in person() { XCTAssertTrue(crop.insetBy(dx: 10, dy: 40).contains(CGPoint(x: p.x, y: p.y))) }
        XCTAssertEqual(tracker.inputRect(imageWidth: 1080, imageHeight: 1920), crop)

        tracker.update(person(dx: 3, dy: -2))
        XCTAssertEqual(tracker.crop, crop, "a few pixels of jitter must not move the crop")
        tracker.update(person(dx: 300))
        XCTAssertNotEqual(tracker.crop, crop, "a person leaving the crop moves it")
        XCTAssertTrue(tracker.crop!.contains(CGPoint(x: 1000, y: 500)))
    }

    func testCropShrinksOnlyPastTheHysteresisBand() throws {
        var tracker = RTMPoseCropTracker()
        tracker.update(person())
        let standing = try XCTUnwrap(tracker.crop)
        // Squat bottom: same width, 0.8× the height — still within maxRatio, crop held.
        let bottom = person().map { PoseKeypoint(x: $0.x, y: 500 + ($0.y - 500) * 0.8 + 100, confidence: $0.confidence) }
        tracker.update(bottom)
        XCTAssertEqual(tracker.crop, standing)
        // Half the size: re-cropped tighter.
        let small = person().map { PoseKeypoint(x: 450 + ($0.x - 400) * 0.5, y: 650 + ($0.y - 500) * 0.5, confidence: $0.confidence) }
        tracker.update(small)
        XCTAssertLessThan(try XCTUnwrap(tracker.crop).height, standing.height * 0.8)
    }

    func testLostPersonFallsBackToWholeFrame() {
        var tracker = RTMPoseCropTracker()
        tracker.update(person())
        XCTAssertNotNil(tracker.crop)
        var lost = person(confidence: 0.1)
        for j in 0..<5 { lost[j].confidence = 0.9 }  // 5 < minJoints
        tracker.update(lost)
        XCTAssertNil(tracker.crop)
        XCTAssertEqual(tracker.inputRect(imageWidth: 1080, imageHeight: 1920), CGRect(x: 0, y: 0, width: 1080, height: 1920))
        tracker.update(person())
        XCTAssertNotNil(tracker.crop, "found again on the whole frame → crop again")
        tracker.reset()
        XCTAssertNil(tracker.crop)
    }

    func testReacquireOptionsDefaultToTheCurrentPath() throws {
        let t = RTMPoseCropTracker()
        XCTAssertEqual(t.lostInput, .stretch)
        XCTAssertNil(t.acquireMinJoints)
        XCTAssertEqual(t.lostHoldFrames, 0)
        XCTAssertEqual(t.lostSearchInterval, 0)
        // Letterbox: 1280×720 in a 3:4 rect, centred, aspect kept.
        var lb = RTMPoseCropTracker()
        lb.lostInput = .letterbox
        let r = lb.inputRect(imageWidth: 1280, imageHeight: 720)
        XCTAssertEqual(r.width, 1280, accuracy: 1e-9)
        XCTAssertEqual(r.height, 1280 / 0.75, accuracy: 1e-9)
        XCTAssertEqual(r.midY, 360, accuracy: 1e-9)
        let tiles = RTMPoseCropTracker.lostSearchRects(imageWidth: 1280, imageHeight: 720)
        XCTAssertEqual(tiles.count, 4)
        XCTAssertEqual(tiles[0], r)
        XCTAssertEqual(tiles[1], CGRect(x: 0, y: 0, width: 540, height: 720))
        XCTAssertEqual(tiles[3], CGRect(x: 740, y: 0, width: 540, height: 720))
        XCTAssertEqual(RTMPoseCropTracker.lostSearchRects(imageWidth: 720, imageHeight: 1280)[3],
                       CGRect(x: 0, y: 320, width: 720, height: 960))
    }

    func testRelaxedAcquireAndHold() {
        var four = person(confidence: 0.1)
        for j in 0..<4 { four[j].confidence = 0.9 }
        var t = RTMPoseCropTracker()
        t.update(four)
        XCTAssertNil(t.crop, "default: 4 joints do not start tracking")
        t.acquireMinJoints = 4
        t.update(four)
        XCTAssertNotNil(t.crop, "relaxed: 4 joints start tracking")
        t.update(four)
        XCTAssertNil(t.crop, "keeping still needs minJoints")
        t.lostHoldFrames = 2
        t.update(person())
        let crop = t.crop
        t.update(person(confidence: 0.1))
        t.update(person(confidence: 0.1))
        XCTAssertEqual(t.crop, crop, "held for 2 frames")
        t.update(person(confidence: 0.1))
        XCTAssertNil(t.crop)
    }

    func testCropRefitsWhenJointsArePinnedToItsBorder() throws {
        for refit in [true, false] {
            var tracker = RTMPoseCropTracker()
            tracker.refitAtCropEdge = refit
            tracker.update(person())
            let crop = try XCTUnwrap(tracker.crop)
            // The person moved left past the crop: RTMPose can only put the head/arm joints on the crop's left
            // edge (MM-Fit w02_s3: nose, shoulders, elbows, wrists all at one x for 120 frames).
            var pinned = person()
            for j in 0..<11 { pinned[j].x = crop.minX }
            tracker.update(pinned)
            if refit {
                XCTAssertLessThan(try XCTUnwrap(tracker.crop).minX, crop.minX, "the crop grows toward the cut side")
                XCTAssertEqual(tracker.edgeRefits, 1)
            } else {
                XCTAssertEqual(tracker.crop, crop, "old: held")
                XCTAssertEqual(tracker.edgeRefits, 0)
            }
        }
        var tracker = RTMPoseCropTracker()
        tracker.update(person())
        tracker.update(person(dx: 3, dy: -2))
        XCTAssertEqual(tracker.edgeRefits, 0, "joints inside the crop never trigger it")
    }

    // MARK: - Wrong-person recheck

    /// Standing bystander (person(): 200×600 box) vs the user lying on the floor (880×300 box, 2.2× the area).
    private func lyingUser(confidence: Double = 0.9) -> [PoseKeypoint] {
        (0..<17).map { j in PoseKeypoint(x: 100 + Double(j) * 55, y: 1300 + Double(j % 4) * 100, confidence: confidence) }
    }

    func testRecheckIsDueEveryIntervalOfTrackedFrames() {
        var tracker = RTMPoseCropTracker()
        tracker.recheckInterval = 3
        XCTAssertFalse(tracker.wholeFrameRecheckDue, "nothing tracked yet: the whole frame already runs")
        tracker.update(person())
        tracker.update(person())
        XCTAssertFalse(tracker.wholeFrameRecheckDue)
        tracker.update(person())
        XCTAssertTrue(tracker.wholeFrameRecheckDue)
        tracker.offerWholeFrame(person(confidence: 0.1))  // nobody found: keep tracking, restart the count
        XCTAssertFalse(tracker.wholeFrameRecheckDue)
        XCTAssertNotNil(tracker.crop)
    }

    func testRecheckSwitchesFromBystanderToClearlyBiggerPersonElsewhere() throws {
        var tracker = RTMPoseCropTracker()
        tracker.update(person())
        let bystander = try XCTUnwrap(tracker.crop)
        XCTAssertTrue(tracker.offerWholeFrame(lyingUser()))
        let crop = try XCTUnwrap(tracker.crop)
        XCTAssertNotEqual(crop, bystander)
        for p in lyingUser() { XCTAssertTrue(crop.contains(CGPoint(x: p.x, y: p.y))) }
        XCTAssertEqual(crop.width / crop.height, 0.75, accuracy: 1e-9)
    }

    func testRecheckKeepsTrackedPersonWhenWholeFrameSeesTheSameOrASmallerOne() throws {
        var tracker = RTMPoseCropTracker()
        tracker.update(lyingUser())
        let user = try XCTUnwrap(tracker.crop)
        // Same person, stretched input jitter: overlaps → kept.
        XCTAssertFalse(tracker.offerWholeFrame(lyingUser().map { PoseKeypoint(x: $0.x + 20, y: $0.y - 15, confidence: $0.confidence) }))
        // Smaller bystander elsewhere → kept.
        XCTAssertFalse(tracker.offerWholeFrame(person()))
        XCTAssertEqual(tracker.crop, user)
    }

    func testRecheckComparesOverlapWithTheCropNotTheKeypointBox() throws {
        var tracker = RTMPoseCropTracker()
        tracker.update(person())  // box 400–600 × 500–1100, crop ≈ 174–826 × 365–1235
        let crop = try XCTUnwrap(tracker.crop)
        // Whole frame: 3× the box area, only 28% inside the keypoint box but all inside the crop
        // (e.g. a half-seen user, or two people mixed into one box) — no switch.
        let wide = (0..<17).map { j in PoseKeypoint(x: 200 + Double(j % 5) * 150, y: 400 + Double(j) * 37.5, confidence: 0.9) }
        XCTAssertFalse(tracker.offerWholeFrame(wide))
        XCTAssertEqual(tracker.crop, crop)
    }

    func testRecheckIgnoresAWeakWholeFrameDetection() throws {
        var tracker = RTMPoseCropTracker()
        tracker.update(person())
        let bystander = try XCTUnwrap(tracker.crop)
        // Big box but seen weakly (mean 0.35): stretched whole frames can mix two people — no switch.
        XCTAssertFalse(tracker.offerWholeFrame(lyingUser(confidence: 0.35)))
        // Big box but only 8 joints: no switch.
        var partial = lyingUser()
        for j in 8..<17 { partial[j].confidence = 0.1 }
        XCTAssertFalse(tracker.offerWholeFrame(partial))
        XCTAssertEqual(tracker.crop, bystander)
    }

    // MARK: - Pixels and coordinates

    /// Black 1080×1920 frame with one white 10×10 square whose top-left is (x, y).
    private func frame(dotAt x: Int, _ y: Int) -> CGImage {
        let width = 1080, height = 1920
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: x, y: height - y - 10, width: 10, height: 10))  // bottom-left origin
        return context.makeImage()!
    }

    /// Brightness-weighted centroid of the red channel in the 192×256 buffer (input pixel centres).
    private func centroid(_ pixels: [UInt8]) -> PosePoint {
        var sx = 0.0, sy = 0.0, sw = 0.0
        for y in 0..<256 {
            for x in 0..<192 {
                let w = Double(pixels[(y * 192 + x) * 4])
                sx += w * (Double(x) + 0.5); sy += w * (Double(y) + 0.5); sw += w
            }
        }
        return PosePoint(x: sx / sw, y: sy / sw)
    }

    func testCropRoundTripMapsInputPixelsBackToFramePixels() throws {
        let image = frame(dotAt: 600, 900)  // centre (605, 905)
        var pixels = [UInt8](repeating: 0, count: 192 * 256 * 4)
        for rect in [CGRect(x: 450, y: 700, width: 300, height: 400),      // inside the frame
                     CGRect(x: 0, y: 0, width: 1080, height: 1920),         // whole frame, stretched
                     CGRect(x: 500, y: 800, width: 750, height: 1000)] {    // reaches past the right edge
            let back = try PosePreprocess.drawRegion(image, rect: rect, into: &pixels)
            let p = back.apply(centroid(pixels))
            let tolerance = max(rect.width / 192, rect.height / 256)  // one input pixel
            XCTAssertEqual(p.x, 605, accuracy: tolerance, "\(rect)")
            XCTAssertEqual(p.y, 905, accuracy: tolerance, "\(rect)")
        }
    }

    func testOutsideTheFrameIsBlackAndOldPixelsAreOverwritten() throws {
        var pixels = [UInt8](repeating: 255, count: 192 * 256 * 4)
        let image = frame(dotAt: 0, 0)
        // Left half of the crop lies outside the frame.
        _ = try PosePreprocess.drawRegion(image, rect: CGRect(x: -300, y: 1000, width: 600, height: 800), into: &pixels)
        for y in stride(from: 0, to: 256, by: 16) {
            XCTAssertEqual(pixels[(y * 192 + 10) * 4], 0)
            XCTAssertEqual(pixels[(y * 192 + 10) * 4 + 3], 255, "opaque black, not left-over or transparent")
        }
    }
}
