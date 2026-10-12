import CoreGraphics
import CoreML
import Foundation

/// Owned by one serial inference queue. Do not normalize/overwrite until prediction returns.
/// Reuses the 192×256 RGBA storage, Float32 tensor and feature provider between frames.
final class RTMPoseInputWorkspace {
    let input: MLMultiArray
    let provider: MLDictionaryFeatureProvider
    var pixels = [UInt8](repeating: 0, count: 192 * 256 * 4)

    init() throws {
        input = try PosePreprocess.makeRTMPoseInputArray()
        provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_image": MLFeatureValue(multiArray: input)
        ])
    }
}

enum PosePreprocessError: Error {
    case missingCGImage
    case couldNotCreateBitmapContext
    case invalidRTMPoseInputCount(Int)
    case invalidRTMPoseInputStrides([Int])
    case invalidPixelBufferCount(Int)
}

/// RTMPose input tensor: shape [1, 3, 256, 192], float32, RGB normalized with the ImageNet
/// mean/std. UIKit-free on purpose; the image side of preprocessing extends this in
/// PosePreprocess.swift.
enum PosePreprocess {
    static let meanRGB = [123.675, 116.28, 103.53]
    static let stdRGB = [58.395, 57.12, 57.375]

    static func makeRTMPoseInputArray() throws -> MLMultiArray {
        let input = try MLMultiArray(
            shape: [
                NSNumber(value: 1),
                NSNumber(value: 3),
                NSNumber(value: PoseCoordinateTransforms.rtmposeInputHeight),
                NSNumber(value: PoseCoordinateTransforms.rtmposeInputWidth),
            ],
            dataType: .float32
        )
        try CoreMLMultiArrayIndexing.validateShape(
            input,
            expectedShape: [1, 3, 256, 192],
            label: "PosePreprocess.rtmpose_input"
        )
        guard input.count == 147456 else {
            throw PosePreprocessError.invalidRTMPoseInputCount(input.count)
        }
        let strides = input.strides.map { $0.intValue }
        guard strides == [147456, 49152, 192, 1] else {
            throw PosePreprocessError.invalidRTMPoseInputStrides(strides)
        }
        return input
    }

    static func normalizeRGBAIntoRTMPoseInput(
        _ pixels: [UInt8],
        input: MLMultiArray,
        width: Int,
        height: Int
    ) throws {
        guard input.count == 147456 else {
            throw PosePreprocessError.invalidRTMPoseInputCount(input.count)
        }
        let pixelCount = width * height
        let expectedPixelBytes = pixelCount * 4
        guard pixels.count == expectedPixelBytes else {
            throw PosePreprocessError.invalidPixelBufferCount(pixels.count)
        }

        let output = input.dataPointer.assumingMemoryBound(to: Float.self)
        let redBase = 0
        let greenBase = pixelCount
        let blueBase = pixelCount * 2
        guard blueBase + pixelCount <= input.count else {
            throw PosePreprocessError.invalidRTMPoseInputCount(input.count)
        }
        let meanR = Float(meanRGB[0])
        let meanG = Float(meanRGB[1])
        let meanB = Float(meanRGB[2])
        let invStdR = Float(1.0 / stdRGB[0])
        let invStdG = Float(1.0 / stdRGB[1])
        let invStdB = Float(1.0 / stdRGB[2])

        for pixelIndex in 0..<pixelCount {
            let byteIndex = pixelIndex * 4
            output[redBase + pixelIndex] = (Float(pixels[byteIndex]) - meanR) * invStdR
            output[greenBase + pixelIndex] = (Float(pixels[byteIndex + 1]) - meanG) * invStdG
            output[blueBase + pixelIndex] = (Float(pixels[byteIndex + 2]) - meanB) * invStdB
        }
    }
}

// MARK: - Top-down person crop (workout camera and pose-replay)

/// Where RTMPose looks in the next frame. RTMPose is top-down: it was trained on a 3:4 box around one
/// person, so the box comes from this frame's keypoints (plus margin), keeps the 3:4 aspect, and is held
/// with hysteresis so keypoint jitter does not move it. Too few confident joints = person lost: the next
/// frame goes back to the whole frame (stretched to 192×256, the old input) to find them again.
/// Same idea as CalibrationFrameAnalyzer.updateCrop, without its calibration-only joint requirements.
///
/// Wrong-person lock: the first whole-frame pass can pick a bystander, and the crop then only ever sees
/// them. So every `recheckInterval` tracked frames the caller also runs the whole frame and passes it to
/// `offerWholeFrame`; a person there who is clearly bigger (`switchAreaRatio`) and mostly outside the
/// tracked one takes over the crop.
struct RTMPoseCropTracker {
    var minConfidence = 0.3
    /// COCO joints at or above `minConfidence` needed to keep tracking.
    var minJoints = 6
    /// Added on every side, as a fraction of the person box.
    var margin = 0.125
    /// The crop is kept while its height is within [minRatio, maxRatio] × a fresh target's.
    var minRatio = 0.8
    var maxRatio = 1.35
    /// Tracked frames between whole-frame rechecks (30 ≈ 1 s; one extra inference each).
    var recheckInterval = 30
    /// A whole-frame person replaces the tracked one when its keypoint box area is this many times larger
    /// and at most `switchMaxOverlap` of it lies inside the current crop.
    var switchAreaRatio = 1.5
    var switchMaxOverlap = 0.3
    /// ...and only if the whole-frame pass saw that person clearly: at least this many joints at
    /// `minConfidence`, with this mean confidence. Stretched whole frames can mix two people into one
    /// box (Exercise3D: wrong switches 6–12 joints, mean 0.33–0.38; right ones 15–17 joints, 0.46–0.71).
    var switchMinJoints = 12
    var switchMinMeanConfidence = 0.42
    /// A confident joint on the crop border (within one input pixel) is pinned there — SimCC cannot point
    /// outside the crop — so the person reaches past it (MM-Fit push-ups: head, shoulders and arms stuck at
    /// one x for 100+ frames, 0 reps). Then the crop is re-fitted around the keypoints (it grows a margin
    /// toward the cut side each frame) instead of being kept. false = keep it (old). docs/decisions.md D-T3-10
    var refitAtCropEdge = true
    /// Frames where `refitAtCropEdge` re-fitted the crop (pose-replay reports it).
    private(set) var edgeRefits = 0
    /// Top-left frame pixels; nil = whole frame.
    private(set) var crop: CGRect?
    /// Confident-keypoint box of the tracked person (frame pixels).
    private(set) var person: CGRect?
    private var framesSinceRecheck = 0

    /// True when the caller should also run the whole frame this frame and call `offerWholeFrame`.
    var wholeFrameRecheckDue: Bool { crop != nil && framesSinceRecheck >= recheckInterval }

    func inputRect(imageWidth: Int, imageHeight: Int) -> CGRect {
        crop ?? CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
    }

    mutating func reset() {
        crop = nil
        person = nil
        framesSinceRecheck = 0
    }

    /// Whole-frame keypoints from a recheck. Switches the crop to that person if they are a different,
    /// clearly bigger person; otherwise keeps tracking.
    @discardableResult
    mutating func offerWholeFrame(_ keypoints: [PoseKeypoint]) -> Bool {
        framesSinceRecheck = 0
        let seen = keypoints.prefix(17).filter { $0.confidence >= minConfidence }
        guard seen.count >= switchMinJoints,
              seen.map(\.confidence).reduce(0, +) / Double(seen.count) >= switchMinMeanConfidence,
              let current = person, let tracked = crop, let candidate = box(keypoints) else { return false }
        let area = { (r: CGRect) in max(r.width, 1) * max(r.height, 1) }
        // Overlap with the crop, not the keypoint box: a half-seen user (only legs confident) has a small
        // box, but the crop still covers them.
        let overlap = candidate.intersection(tracked)
        let inside = overlap.isNull ? 0 : area(overlap) / area(candidate)
        guard area(candidate) >= switchAreaRatio * area(current), inside <= switchMaxOverlap else { return false }
        crop = nil
        update(keypoints)
        return true
    }

    private func box(_ keypoints: [PoseKeypoint]) -> CGRect? {
        let points = keypoints.prefix(17).filter { $0.confidence >= minConfidence }
        guard points.count >= minJoints else { return nil }
        let x0 = points.map(\.x).min()!, x1 = points.map(\.x).max()!
        let y0 = points.map(\.y).min()!, y1 = points.map(\.y).max()!
        guard x1 - x0 > 1 || y1 - y0 > 1 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Feed the frame's COCO-17 keypoints in full-frame pixels (extra Halpe joints are ignored).
    mutating func update(_ keypoints: [PoseKeypoint]) {
        guard let box = box(keypoints) else {
            reset()
            return
        }
        self.person = box
        framesSinceRecheck += 1
        // Keypoints stop at the eyes and ankles; leave room for the head top and the soles.
        let person = box.insetBy(dx: 0, dy: -0.08 * box.height)
        let target = Self.fitToInputAspect(person.insetBy(dx: -margin * person.width, dy: -margin * person.height))
        if let current = crop, current.contains(person),
           current.height > minRatio * target.height, current.height < maxRatio * target.height {
            let tx = current.width / Double(PoseCoordinateTransforms.rtmposeInputWidth)
            let ty = current.height / Double(PoseCoordinateTransforms.rtmposeInputHeight)
            guard refitAtCropEdge, !current.insetBy(dx: tx, dy: ty).contains(box) else { return }
            edgeRefits += 1
        }
        crop = target
    }

    /// Grows `rect` around its centre to the RTMPose input aspect (3:4).
    static func fitToInputAspect(_ rect: CGRect) -> CGRect {
        let aspect = Double(PoseCoordinateTransforms.rtmposeInputWidth) / Double(PoseCoordinateTransforms.rtmposeInputHeight)
        var width = rect.width, height = rect.height
        if width / max(height, 1e-9) > aspect {
            height = width / aspect
        } else {
            width = height * aspect
        }
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
}

extension PosePreprocess {
    /// Draws `rect` of `image` (top-left frame pixels, may reach past the frame) into the 192×256 RGBA
    /// buffer; outside the frame is black, like RTMPose's zero-border affine crop. A 3:4 rect keeps the
    /// aspect; the whole frame is stretched as before. Returns input pixel → frame pixel.
    static func drawRegion(_ image: CGImage, rect: CGRect, into pixels: inout [UInt8]) throws -> Affine2x3 {
        let width = PoseCoordinateTransforms.rtmposeInputWidth
        let height = PoseCoordinateTransforms.rtmposeInputHeight
        let sx = Double(width) / rect.width, sy = Double(height) / rect.height
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw PosePreprocessError.couldNotCreateBitmapContext
            }
            context.interpolationQuality = .high
            // The bitmap is reused: overwrite, never blend over the last frame.
            context.setBlendMode(.copy)
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Core Graphics is bottom-left based; bitmap rows still come out top to bottom.
            context.draw(image, in: CGRect(x: -rect.minX * sx,
                                           y: Double(height) - (Double(image.height) - rect.minY) * sy,
                                           width: Double(image.width) * sx, height: Double(image.height) * sy))
        }
        return Affine2x3(a: 1 / sx, b: 0, c: rect.minX, d: 0, e: 1 / sy, f: rect.minY)
    }
}

extension RTMPoseCropTracker {
    /// The recheck pass: RTMPose on the whole frame (stretched, like a lost-person frame), COCO-17 in frame
    /// pixels, offered to the tracker. Returns true if the crop switched person. Reuses `workspace`.
    @discardableResult
    mutating func recheckWholeFrame(_ image: CGImage, model: MLModel, workspace: RTMPoseInputWorkspace) throws -> Bool {
        let whole = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let back = try PosePreprocess.drawRegion(image, rect: whole, into: &workspace.pixels)
        try PosePreprocess.normalizeRGBAIntoRTMPoseInput(workspace.pixels, input: workspace.input,
                                                          width: PoseCoordinateTransforms.rtmposeInputWidth,
                                                          height: PoseCoordinateTransforms.rtmposeInputHeight)
        let output = try model.prediction(from: workspace.provider)
        guard let x = output.featureValue(for: "simcc_x")?.multiArrayValue,
              let y = output.featureValue(for: "simcc_y")?.multiArrayValue else { return false }
        let decoded = try SimCCDecoder.decodeToInputCoordinates(simccX: x, simccY: y)
        return offerWholeFrame(PoseCoordinateTransforms.applyInverseAffine(decoded: decoded, inverseAffine: back))
    }
}

/// One frame of the live pose step: decoded output, input → frame transform, COCO-17 in frame pixels, and
/// whether the whole-frame recheck ran (nil) or switched person (true/false).
struct RTMPoseFrameEstimate {
    let decoded: SimCCDecodeResult
    let inverseAffine: Affine2x3
    let coco17: [PoseKeypoint]
    let recheckSwitched: Bool?
}

extension RTMPoseCropTracker {
    /// The per-frame body pose step of the live camera path: RTMPose on the tracked 3:4 crop (whole frame
    /// when the person is lost, or always when `personCrop` is false), keypoints back to frame pixels, tracker
    /// update, then the ~1 s whole-frame recheck. CameraPosePreview, pose-replay and the on-device pipeline
    /// bench (tools/pose_model_bench) all call this. nil when the model has no SimCC outputs.
    mutating func estimate(_ image: CGImage, model: MLModel, workspace: RTMPoseInputWorkspace,
                           personCrop: Bool = true) throws -> RTMPoseFrameEstimate? {
        let rect = personCrop ? inputRect(imageWidth: image.width, imageHeight: image.height)
            : CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let back = try PosePreprocess.drawRegion(image, rect: rect, into: &workspace.pixels)
        try PosePreprocess.normalizeRGBAIntoRTMPoseInput(workspace.pixels, input: workspace.input,
                                                          width: PoseCoordinateTransforms.rtmposeInputWidth,
                                                          height: PoseCoordinateTransforms.rtmposeInputHeight)
        let output = try model.prediction(from: workspace.provider)
        guard let x = output.featureValue(for: "simcc_x")?.multiArrayValue,
              let y = output.featureValue(for: "simcc_y")?.multiArrayValue else { return nil }
        let decoded = try SimCCDecoder.decodeToInputCoordinates(simccX: x, simccY: y)
        let coco17 = PoseCoordinateTransforms.applyInverseAffine(decoded: decoded, inverseAffine: back)
        var switched: Bool?
        if personCrop {
            update(coco17)
            // Every ~1 s one extra whole-frame pass, so a bystander locked in at the start is dropped for the
            // (bigger) user. Runs after this frame's keypoints are taken from the workspace.
            if wholeFrameRecheckDue { switched = try recheckWholeFrame(image, model: model, workspace: workspace) }
        }
        return RTMPoseFrameEstimate(decoded: decoded, inverseAffine: back, coco17: coco17, recheckSwitched: switched)
    }
}
