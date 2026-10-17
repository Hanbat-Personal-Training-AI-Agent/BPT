import CoreGraphics
import XCTest
@testable import CalibrationEngineKit

final class CropSequenceTests: XCTestCase {
    /// pose-replay `--crops-in` reads back exactly the trace it writes (rects to 1/1000 px, whole frame stays whole,
    /// frames absent from the file stay absent so the replay can count them).
    func testTraceRoundTrip() {
        let rect = CGRect(x: -12.5, y: 40.25, width: 300, height: 400)
        let text = [CropSequence.header,
                    CropSequence.line(frame: 0, rect: nil, source: "full"),
                    CropSequence.line(frame: 1, rect: rect, source: "retarget", recheck: "kept"),
                    CropSequence.line(frame: 3, rect: rect, source: "kept")].joined(separator: "\n")
        let parsed = CropSequence.parse(text)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0], .some(nil))
        XCTAssertEqual(parsed[1], .some(rect))
        XCTAssertFalse(parsed.keys.contains(2))
        XCTAssertEqual(parsed[3], .some(rect))
        // Detector files may carry only frame,x,y,w,h.
        XCTAssertEqual(CropSequence.parse("frame,x,y,w,h\n7,1,2,3,4\n")[7], .some(CGRect(x: 1, y: 2, width: 3, height: 4)))
    }
}
