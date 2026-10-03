import CoreGraphics
import CoreML
import Foundation
import QuartzCore
import UIKit

struct PosePreprocessTiming {
    var resizeMs: Double = 0.0
    var pixelExtractMs: Double = 0.0
    var normalizeToMultiArrayMs: Double = 0.0
}

struct PosePreprocessResult {
    let inputTensor: MLMultiArray
    let inverseAffine: Affine2x3
    let imageWidth: Int
    let imageHeight: Int
    let timing: PosePreprocessTiming
}

// The tensor half of `PosePreprocess` (normalization constants, input array, RGBA → tensor)
// lives in RTMPoseInputTensor.swift without UIKit, so the calibration replay tool can build it on macOS.
extension PosePreprocess {

    static func makeSyntheticImage(width: Int = 1080, height: Int = 1920) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(white: 0.08, alpha: 1.0).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

            for y in stride(from: 0, to: height, by: 16) {
                let intensity = CGFloat(y) / CGFloat(max(height - 1, 1))
                UIColor(
                    red: 0.12 + 0.30 * intensity,
                    green: 0.18 + 0.20 * intensity,
                    blue: 0.24 + 0.18 * intensity,
                    alpha: 1.0
                ).setFill()
                cg.fill(CGRect(x: 0, y: y, width: width, height: 16))
            }

            UIColor(red: 0.85, green: 0.82, blue: 0.72, alpha: 1.0).setStroke()
            cg.setLineWidth(12.0)
            let centerX = CGFloat(width) * 0.52
            let shoulderY = CGFloat(height) * 0.31
            let hipY = CGFloat(height) * 0.58
            cg.move(to: CGPoint(x: centerX - 130.0, y: shoulderY))
            cg.addLine(to: CGPoint(x: centerX + 130.0, y: shoulderY))
            cg.move(to: CGPoint(x: centerX, y: shoulderY))
            cg.addLine(to: CGPoint(x: centerX, y: hipY))
            cg.move(to: CGPoint(x: centerX - 95.0, y: hipY))
            cg.addLine(to: CGPoint(x: centerX + 95.0, y: hipY))
            cg.move(to: CGPoint(x: centerX - 130.0, y: shoulderY))
            cg.addLine(to: CGPoint(x: centerX - 215.0, y: shoulderY + 190.0))
            cg.move(to: CGPoint(x: centerX + 130.0, y: shoulderY))
            cg.addLine(to: CGPoint(x: centerX + 215.0, y: shoulderY + 190.0))
            cg.strokePath()

            UIColor(red: 0.96, green: 0.76, blue: 0.55, alpha: 1.0).setFill()
            cg.fillEllipse(in: CGRect(x: centerX - 54.0, y: shoulderY - 142.0, width: 108.0, height: 108.0))
        }
    }

    static func preprocessFullImage(_ image: UIImage) throws -> PosePreprocessResult {
        guard let cgImage = image.cgImage else {
            throw PosePreprocessError.missingCGImage
        }
        return try preprocessFullImage(cgImage)
    }

    static func preprocessFullImage(_ cgImage: CGImage) throws -> PosePreprocessResult {
        try preprocessFullImageFast(cgImage)
    }

    static func preprocessFullImageFast(_ image: UIImage) throws -> PosePreprocessResult {
        guard let cgImage = image.cgImage else {
            throw PosePreprocessError.missingCGImage
        }
        return try preprocessFullImageFast(cgImage)
    }

    static func preprocessFullImageFast(_ cgImage: CGImage) throws -> PosePreprocessResult {
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        let inputWidth = PoseCoordinateTransforms.rtmposeInputWidth
        let inputHeight = PoseCoordinateTransforms.rtmposeInputHeight

        var timing = PosePreprocessTiming()
        let pixelExtractStart = CACurrentMediaTime()
        var pixels = Array(repeating: UInt8(0), count: inputWidth * inputHeight * 4)
        timing.pixelExtractMs = elapsedMs(pixelExtractStart)

        let resizeStart = CACurrentMediaTime()
        try drawResizedRGBA(
            cgImage,
            pixels: &pixels,
            width: inputWidth,
            height: inputHeight
        )
        timing.resizeMs = elapsedMs(resizeStart)

        let input = try makeRTMPoseInputArray()
        let normalizeStart = CACurrentMediaTime()
        try normalizeRGBAIntoRTMPoseInput(pixels, input: input, width: inputWidth, height: inputHeight)
        timing.normalizeToMultiArrayMs = elapsedMs(normalizeStart)

        return PosePreprocessResult(
            inputTensor: input,
            inverseAffine: directResizeInverseAffine(
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                inputWidth: inputWidth,
                inputHeight: inputHeight
            ),
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            timing: timing
        )
    }

    static func preprocessFullImageAffineFallback(_ image: UIImage) throws -> PosePreprocessResult {
        guard let cgImage = image.cgImage else {
            throw PosePreprocessError.missingCGImage
        }

        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        let transforms = try PoseCoordinateTransforms.fullImageTransforms(
            imageWidth: imageWidth,
            imageHeight: imageHeight
        )
        let pixelExtractStart = CACurrentMediaTime()
        let pixels = try rgbaPixels(from: cgImage)
        let pixelExtractMs = elapsedMs(pixelExtractStart)
        let inputWidth = PoseCoordinateTransforms.rtmposeInputWidth
        let inputHeight = PoseCoordinateTransforms.rtmposeInputHeight
        let input = try makeRTMPoseInputArray()

        let normalizeStart = CACurrentMediaTime()
        for y in 0..<inputHeight {
            for x in 0..<inputWidth {
                let sourcePoint = transforms.inverse.apply(PosePoint(x: Double(x), y: Double(y)))
                let rgb = sampleBilinearRGB(
                    pixels: pixels,
                    width: imageWidth,
                    height: imageHeight,
                    x: sourcePoint.x,
                    y: sourcePoint.y
                )
                let values = [rgb.r, rgb.g, rgb.b]
                for channel in 0..<3 {
                    let normalized = (values[channel] - meanRGB[channel]) / stdRGB[channel]
                    let offset = CoreMLMultiArrayIndexing.rtmposeImageInputOffset(
                        channel: channel,
                        y: y,
                        x: x
                    )
                    try CoreMLMultiArrayIndexing.setFloat(
                        input,
                        offset: offset,
                        value: Float(normalized),
                        label: "PosePreprocess.rtmpose_input"
                    )
                }
            }
        }
        let normalizeMs = elapsedMs(normalizeStart)

        return PosePreprocessResult(
            inputTensor: input,
            inverseAffine: transforms.inverse,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            timing: PosePreprocessTiming(
                resizeMs: 0.0,
                pixelExtractMs: pixelExtractMs,
                normalizeToMultiArrayMs: normalizeMs
            )
        )
    }

    private static func directResizeInverseAffine(
        imageWidth: Int,
        imageHeight: Int,
        inputWidth: Int,
        inputHeight: Int
    ) -> Affine2x3 {
        Affine2x3(
            a: Double(imageWidth) / Double(inputWidth),
            b: 0.0,
            c: 0.0,
            d: 0.0,
            e: Double(imageHeight) / Double(inputHeight),
            f: 0.0
        )
    }

    private static func drawResizedRGBA(
        _ cgImage: CGImage,
        pixels: inout [UInt8],
        width: Int,
        height: Int
    ) throws {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        try pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                throw PosePreprocessError.couldNotCreateBitmapContext
            }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private static func rgbaPixels(from cgImage: CGImage) throws -> [UInt8] {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = Array(repeating: UInt8(0), count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let drewImage = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drewImage else {
            throw PosePreprocessError.couldNotCreateBitmapContext
        }
        return pixels
    }

    private static func sampleBilinearRGB(
        pixels: [UInt8],
        width: Int,
        height: Int,
        x: Double,
        y: Double
    ) -> (r: Double, g: Double, b: Double) {
        if x < 0.0 || y < 0.0 || x > Double(width - 1) || y > Double(height - 1) {
            return (0.0, 0.0, 0.0)
        }

        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let wx = x - Double(x0)
        let wy = y - Double(y0)

        let c00 = rgbAt(pixels: pixels, width: width, x: x0, y: y0)
        let c10 = rgbAt(pixels: pixels, width: width, x: x1, y: y0)
        let c01 = rgbAt(pixels: pixels, width: width, x: x0, y: y1)
        let c11 = rgbAt(pixels: pixels, width: width, x: x1, y: y1)

        func interp(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            let top = a * (1.0 - wx) + b * wx
            let bottom = c * (1.0 - wx) + d * wx
            return top * (1.0 - wy) + bottom * wy
        }

        return (
            interp(c00.r, c10.r, c01.r, c11.r),
            interp(c00.g, c10.g, c01.g, c11.g),
            interp(c00.b, c10.b, c01.b, c11.b)
        )
    }

    private static func rgbAt(
        pixels: [UInt8],
        width: Int,
        x: Int,
        y: Int
    ) -> (r: Double, g: Double, b: Double) {
        let offset = (y * width + x) * 4
        return (
            Double(pixels[offset]),
            Double(pixels[offset + 1]),
            Double(pixels[offset + 2])
        )
    }

    private static func elapsedMs(_ start: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - start) * 1000.0
    }
}
