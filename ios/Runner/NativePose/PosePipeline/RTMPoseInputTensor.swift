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
