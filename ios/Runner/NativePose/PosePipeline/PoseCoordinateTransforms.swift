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

    static func normalizedMotionAGFormerFrame(
        fromCOCO17 coco17: [PoseKeypoint],
        imageWidth: Int,
        imageHeight: Int
    ) throws -> [[Float]] {
        let h36m = try coco17ToH36M17(coco17)
        return normalizeMotionAGFormer2D(h36m, imageWidth: imageWidth, imageHeight: imageHeight)
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

    static func normalizeMotionAGFormer2D(
        _ h36m17: [PoseKeypoint],
        imageWidth: Int,
        imageHeight: Int
    ) -> [[Float]] {
        let width = Double(imageWidth)
        let heightOverWidth = Double(imageHeight) / width
        return h36m17.map { keypoint in
            let normalizedX = keypoint.x / width * 2.0 - 1.0
            let normalizedY = keypoint.y / width * 2.0 - heightOverWidth
            return [Float(normalizedX), Float(normalizedY), Float(keypoint.confidence)]
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
