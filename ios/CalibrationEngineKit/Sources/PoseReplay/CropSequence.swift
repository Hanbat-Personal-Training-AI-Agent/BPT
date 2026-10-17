import CoreGraphics
import CoreML
import Foundation

/// Per-frame RTMPose input rects for pose-replay: `<video>_<exercise>_<model>_crops.csv` (the trace every run
/// writes) and `--crops-in PATH` (replay a rect sequence instead of the crop tracker — another model's trace or
/// detector boxes, so two models can be compared on the same input). docs/decisions.md D-T3-19.
/// CSV `frame,x,y,w,h,source,recheck` in top-left frame pixels; empty x = whole frame (stretched, like a lost person).
/// Tool-only (not in ios/Runner).
enum CropSequence {
    static let header = "frame,x,y,w,h,source,recheck"

    static func line(frame: Int, rect: CGRect?, source: String, recheck: String = "") -> String {
        let r = rect.map { [$0.minX, $0.minY, $0.width, $0.height].map { String(format: "%.3f", $0) } }
            ?? ["", "", "", ""]
        return ([String(frame)] + r + [source, recheck]).joined(separator: ",")
    }

    /// frame → rect (nil = whole frame). Frames missing from the file are absent from the map.
    static func parse(_ text: String) -> [Int: CGRect?] {
        var rects: [Int: CGRect?] = [:]
        for row in text.split(whereSeparator: \.isNewline).dropFirst() {
            let c = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 5, let frame = Int(c[0]) else { continue }
            if let x = Double(c[1]), let y = Double(c[2]), let w = Double(c[3]), let h = Double(c[4]), w > 0, h > 0 {
                rects[frame] = CGRect(x: x, y: y, width: w, height: h)
            } else {
                rects[frame] = .some(nil)
            }
        }
        return rects
    }
}

extension RTMPoseCropTracker {
    /// RTMPose on a given rect (no tracker update, no recheck) — the same steps as `estimate`.
    static func estimate(_ image: CGImage, rect: CGRect, model: MLModel,
                         workspace: RTMPoseInputWorkspace) throws -> RTMPoseFrameEstimate? {
        let back = try PosePreprocess.drawRegion(image, rect: rect, into: &workspace.pixels)
        try PosePreprocess.normalizeRGBAIntoRTMPoseInput(workspace.pixels, input: workspace.input,
                                                          width: PoseCoordinateTransforms.rtmposeInputWidth,
                                                          height: PoseCoordinateTransforms.rtmposeInputHeight)
        let output = try model.prediction(from: workspace.provider)
        guard let x = output.featureValue(for: "simcc_x")?.multiArrayValue,
              let y = output.featureValue(for: "simcc_y")?.multiArrayValue else { return nil }
        let decoded = try SimCCDecoder.decodeToInputCoordinates(simccX: x, simccY: y)
        return RTMPoseFrameEstimate(decoded: decoded, inverseAffine: back,
                                    coco17: PoseCoordinateTransforms.applyInverseAffine(decoded: decoded, inverseAffine: back),
                                    recheckSwitched: nil)
    }
}
