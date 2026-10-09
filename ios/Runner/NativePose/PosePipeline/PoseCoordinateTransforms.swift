import Foundation

struct PosePoint {
    var x: Double
    var y: Double
}

struct PoseKeypoint {
    var x: Double
    var y: Double
    var confidence: Double
}

struct Affine2x3 {
    let a: Double
    let b: Double
    let c: Double
    let d: Double
    let e: Double
    let f: Double

    func apply(_ point: PosePoint) -> PosePoint {
        PosePoint(
            x: a * point.x + b * point.y + c,
            y: d * point.x + e * point.y + f
        )
    }
}

enum PoseCoordinateTransformError: Error {
    case singularAffine
    case invalidKeypointCount(Int)
    case invalidImageSize
}

enum PoseCoordinateTransforms {
    static let rtmposeInputWidth = 192
    static let rtmposeInputHeight = 256
    static let simccSplitRatio = 2.0

    static func fullImageTransforms(
        imageWidth: Int,
        imageHeight: Int,
        inputWidth: Int = rtmposeInputWidth,
        inputHeight: Int = rtmposeInputHeight
    ) throws -> (warp: Affine2x3, inverse: Affine2x3) {
        guard imageWidth > 0, imageHeight > 0 else {
            throw PoseCoordinateTransformError.invalidImageSize
        }

        let center = PosePoint(
            x: Double(imageWidth) * 0.5,
            y: Double(imageHeight) * 0.5
        )
        let rawScale = PosePoint(
            x: Double(imageWidth) * 1.25,
            y: Double(imageHeight) * 1.25
        )
        let scale = fixAspectRatio(
            scale: rawScale,
            aspectRatio: Double(inputWidth) / Double(inputHeight)
        )

        let warp = try getWarpMatrix(
            center: center,
            scale: scale,
            outputWidth: inputWidth,
            outputHeight: inputHeight,
            inverse: false
        )
        let inverse = try getWarpMatrix(
            center: center,
            scale: scale,
            outputWidth: inputWidth,
            outputHeight: inputHeight,
            inverse: true
        )
        return (warp, inverse)
    }

    static func fixAspectRatio(scale: PosePoint, aspectRatio: Double) -> PosePoint {
        if scale.x > scale.y * aspectRatio {
            return PosePoint(x: scale.x, y: scale.x / aspectRatio)
        }
        return PosePoint(x: scale.y * aspectRatio, y: scale.y)
    }

    static func getWarpMatrix(
        center: PosePoint,
        scale: PosePoint,
        outputWidth: Int,
        outputHeight: Int,
        inverse: Bool
    ) throws -> Affine2x3 {
        let srcDir = rotatePoint(PosePoint(x: scale.x * -0.5, y: 0.0), angleRadians: 0.0)
        let dstDir = PosePoint(x: Double(outputWidth) * -0.5, y: 0.0)

        let src0 = center
        let src1 = PosePoint(x: center.x + srcDir.x, y: center.y + srcDir.y)
        let src2 = thirdPoint(src0, src1)

        let dst0 = PosePoint(x: Double(outputWidth) * 0.5, y: Double(outputHeight) * 0.5)
        let dst1 = PosePoint(x: dst0.x + dstDir.x, y: dst0.y + dstDir.y)
        let dst2 = thirdPoint(dst0, dst1)

        if inverse {
            return try affineTransform(from: [dst0, dst1, dst2], to: [src0, src1, src2])
        }
        return try affineTransform(from: [src0, src1, src2], to: [dst0, dst1, dst2])
    }

    static func rotatePoint(_ point: PosePoint, angleRadians: Double) -> PosePoint {
        let sine = sin(angleRadians)
        let cosine = cos(angleRadians)
        return PosePoint(
            x: point.x * cosine - point.y * sine,
            y: point.x * sine + point.y * cosine
        )
    }

    static func thirdPoint(_ a: PosePoint, _ b: PosePoint) -> PosePoint {
        let direction = PosePoint(x: a.x - b.x, y: a.y - b.y)
        return PosePoint(x: b.x - direction.y, y: b.y + direction.x)
    }

    static func applyInverseAffine(
        decoded: SimCCDecodeResult,
        inverseAffine: Affine2x3
    ) -> [PoseKeypoint] {
        zip(decoded.inputCoordinates, decoded.confidences).map { point, confidence in
            let imagePoint = inverseAffine.apply(point)
            return PoseKeypoint(x: imagePoint.x, y: imagePoint.y, confidence: confidence)
        }
    }

    /// Halpe26 toes and heels through the same inverse affine; nil for the COCO17 model.
    static func applyInverseAffineToFeet(
        decoded: SimCCDecodeResult,
        inverseAffine: Affine2x3
    ) -> FootKeypoints? {
        let offset = SimCCDecoder.cocoJointCount
        guard decoded.extraInputCoordinates.count == Halpe26.jointCount - offset else { return nil }
        func point(_ index: Int) -> PoseKeypoint {
            let p = inverseAffine.apply(decoded.extraInputCoordinates[index - offset])
            return PoseKeypoint(x: p.x, y: p.y, confidence: decoded.extraConfidences[index - offset])
        }
        return FootKeypoints(
            leftBigToe: point(Halpe26.leftBigToe),
            rightBigToe: point(Halpe26.rightBigToe),
            leftSmallToe: point(Halpe26.leftSmallToe),
            rightSmallToe: point(Halpe26.rightSmallToe),
            leftHeel: point(Halpe26.leftHeel),
            rightHeel: point(Halpe26.rightHeel)
        )
    }

    /// One frame of MotionAGFormer input ([17][x, y, confidence]). Call in frame order with the
    /// same `normalizer` for the whole session: `.personCrop` keeps a crop across frames.
    static func normalizedMotionAGFormerFrame(
        fromCOCO17 coco17: [PoseKeypoint],
        imageWidth: Int,
        imageHeight: Int,
        normalizer: inout MotionAGFormerInputNormalizer
    ) throws -> [[Float]] {
        let h36m = try coco17ToH36M17(coco17)
        return normalizer.normalize(h36m, imageWidth: imageWidth, imageHeight: imageHeight)
    }

    static func coco17ToH36M17(_ coco17: [PoseKeypoint]) throws -> [PoseKeypoint] {
        guard coco17.count == 17 else {
            throw PoseCoordinateTransformError.invalidKeypointCount(coco17.count)
        }

        var output = Array(repeating: PoseKeypoint(x: 0.0, y: 0.0, confidence: 0.0), count: 17)
        output[0] = average(coco17[11], coco17[12])
        output[1] = coco17[12]
        output[2] = coco17[14]
        output[3] = coco17[16]
        output[4] = coco17[11]
        output[5] = coco17[13]
        output[6] = coco17[15]
        output[8] = average(coco17[5], coco17[6])
        output[7] = average(output[0], output[8])
        output[9] = average(coco17[0], output[8])
        output[10] = average(coco17[1], coco17[2])
        output[11] = coco17[5]
        output[12] = coco17[7]
        output[13] = coco17[9]
        output[14] = coco17[6]
        output[15] = coco17[8]
        output[16] = coco17[10]
        return output
    }

    /// p -> (p - centre) / side * 2 for every joint; confidence passes through.
    static func squareCropNormalize(_ h36m17: [PoseKeypoint], crop: SquareCrop) -> [[Float]] {
        h36m17.map { keypoint in
            [Float((keypoint.x - crop.centerX) / crop.side * 2.0),
             Float((keypoint.y - crop.centerY) / crop.side * 2.0),
             Float(keypoint.confidence)]
        }
    }

    private static func average(_ a: PoseKeypoint, _ b: PoseKeypoint) -> PoseKeypoint {
        PoseKeypoint(
            x: (a.x + b.x) * 0.5,
            y: (a.y + b.y) * 0.5,
            confidence: (a.confidence + b.confidence) * 0.5
        )
    }

    private static func affineTransform(from src: [PosePoint], to dst: [PosePoint]) throws -> Affine2x3 {
        let matrix = [
            [src[0].x, src[0].y, 1.0],
            [src[1].x, src[1].y, 1.0],
            [src[2].x, src[2].y, 1.0],
        ]
        let inverse = try inverse3x3(matrix)
        let xParams = multiply(inverse, [dst[0].x, dst[1].x, dst[2].x])
        let yParams = multiply(inverse, [dst[0].y, dst[1].y, dst[2].y])
        return Affine2x3(
            a: xParams[0],
            b: xParams[1],
            c: xParams[2],
            d: yParams[0],
            e: yParams[1],
            f: yParams[2]
        )
    }

    private static func inverse3x3(_ m: [[Double]]) throws -> [[Double]] {
        let a = m[0][0], b = m[0][1], c = m[0][2]
        let d = m[1][0], e = m[1][1], f = m[1][2]
        let g = m[2][0], h = m[2][1], i = m[2][2]

        let a11 = e * i - f * h
        let a12 = -(d * i - f * g)
        let a13 = d * h - e * g
        let a21 = -(b * i - c * h)
        let a22 = a * i - c * g
        let a23 = -(a * h - b * g)
        let a31 = b * f - c * e
        let a32 = -(a * f - c * d)
        let a33 = a * e - b * d

        let determinant = a * a11 + b * a12 + c * a13
        guard abs(determinant) > 1e-12 else {
            throw PoseCoordinateTransformError.singularAffine
        }
        let invDet = 1.0 / determinant
        return [
            [a11 * invDet, a21 * invDet, a31 * invDet],
            [a12 * invDet, a22 * invDet, a32 * invDet],
            [a13 * invDet, a23 * invDet, a33 * invDet],
        ]
    }

    private static func multiply(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        matrix.map { row in
            row[0] * vector[0] + row[1] * vector[1] + row[2] * vector[2]
        }
    }
}

/// MotionAGFormer 2D-input normalization; mirrors pose_feedback/body/motionagformer_adapter.py and
/// docs/research/rtmpose_motionagformer_image_to_pose_pipeline.md §13. Every method is the same
/// square-crop map with a different crop. Only the 3D lifter input uses it: 2D evaluators and
/// calibration keep pixel keypoints.
enum MotionAGFormerNormalization: String {
    /// VideoPose3D screen coordinates (x/W*2-1, y/W*2-H/W). Portrait video puts y at +-H/W.
    case screen
    /// Image centre, side = max(W, H): both axes within +-1.
    case longSide = "long_side"
    /// Person-centred square crop held with hysteresis (PersonSquareCropTracker).
    case personCrop = "person_crop"

    /// Single switch back to the old behaviour: set to `.screen`.
    static let default3D: MotionAGFormerNormalization = .personCrop
}

struct SquareCrop: Equatable {
    var centerX: Double
    var centerY: Double
    var side: Double

    /// Image-level crop for `.screen` / `.longSide`; `.personCrop` falls back to `.longSide`.
    static func image(width: Int, height: Int, normalization: MotionAGFormerNormalization) -> SquareCrop {
        let side = normalization == .screen ? Double(width) : Double(max(width, height))
        return SquareCrop(centerX: Double(width) * 0.5, centerY: Double(height) * 0.5, side: side)
    }
}

/// Square crop around the person, held still with hysteresis like CalibrationFrameAnalyzer.updateCrop:
/// it only moves when the person leaves it or its size leaves [minRatio, maxRatio] x the fresh target.
/// The band is wide on the large side so a squat (bbox ~0.6x) does not shrink the crop.
struct PersonSquareCropTracker {
    var margin = 2.0
    var minConfidence = 0.3
    var minRatio = 0.8
    var maxRatio = 2.0
    private(set) var crop: SquareCrop?

    /// Feed one H36M17 frame; nil until the first frame with a usable bbox, then the last crop
    /// through dropouts.
    mutating func update(_ joints: [PoseKeypoint]) -> SquareCrop? {
        let points = joints.filter { $0.confidence >= minConfidence }
        guard points.count >= 2 else { return crop }
        let xs = points.map(\.x), ys = points.map(\.y)
        let x0 = xs.min()!, x1 = xs.max()!
        var y0 = ys.min()!, y1 = ys.max()!
        guard x1 - x0 > 1, y1 - y0 > 1 else { return crop }
        let pad = 0.08 * (y1 - y0)  // keypoints stop at the eyes and ankles
        y0 -= pad
        y1 += pad
        let target = SquareCrop(centerX: (x0 + x1) * 0.5, centerY: (y0 + y1) * 0.5,
                                side: max(x1 - x0, y1 - y0) * margin)
        if let current = crop {
            let h = current.side * 0.5
            let inside = current.centerX - h <= x0 && x1 <= current.centerX + h
                && current.centerY - h <= y0 && y1 <= current.centerY + h
            if inside && minRatio * target.side < current.side && current.side < maxRatio * target.side {
                return current
            }
        }
        crop = target
        return target
    }
}

struct MotionAGFormerInputNormalizer {
    var normalization: MotionAGFormerNormalization = .default3D
    var tracker = PersonSquareCropTracker()

    mutating func normalize(_ h36m17: [PoseKeypoint], imageWidth: Int, imageHeight: Int) -> [[Float]] {
        let crop: SquareCrop
        if normalization == .personCrop {
            crop = tracker.update(h36m17)
                ?? SquareCrop.image(width: imageWidth, height: imageHeight, normalization: .longSide)
        } else {
            crop = SquareCrop.image(width: imageWidth, height: imageHeight, normalization: normalization)
        }
        return PoseCoordinateTransforms.squareCropNormalize(h36m17, crop: crop)
    }
}
