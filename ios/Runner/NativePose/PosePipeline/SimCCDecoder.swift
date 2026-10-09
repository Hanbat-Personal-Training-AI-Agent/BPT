import CoreML
import Foundation

enum CoreMLMultiArrayIndexingError: Error {
    case invalidShape(label: String, actual: [Int], expected: [Int])
    case offsetOutOfBounds(label: String, offset: Int, count: Int, shape: [Int], strides: [Int])
}

enum CoreMLMultiArrayIndexing {
    static func validateShape(_ array: MLMultiArray, expectedShape: [Int], label: String) throws {
        let actual = shape(array)
        guard actual == expectedShape else {
            print("""
            MLMultiArray shape mismatch [\(label)]
              actual_shape=\(actual)
              expected_shape=\(expectedShape)
              strides=\(strides(array))
              count=\(array.count)
            """)
            throw CoreMLMultiArrayIndexingError.invalidShape(
                label: label,
                actual: actual,
                expected: expectedShape
            )
        }
    }

    static func logArray(_ array: MLMultiArray, label: String) {
        print("\(label): shape=\(shape(array)) strides=\(strides(array)) count=\(array.count)")
    }

    static func rtmposeImageInputOffset(channel: Int, y: Int, x: Int) -> Int {
        channel * 256 * 192 + y * 192 + x
    }

    static func simccXOffset(joint: Int, xIndex: Int) -> Int {
        joint * 384 + xIndex
    }

    static func simccYOffset(joint: Int, yIndex: Int) -> Int {
        joint * 512 + yIndex
    }

    static func motionAGFormerOffset(t: Int, joint: Int, coord: Int) -> Int {
        t * 17 * 3 + joint * 3 + coord
    }

    static func setFloat(_ array: MLMultiArray, offset: Int, value: Float, label: String) throws {
        try validateOffset(offset, in: array, label: label)
        array[offset] = NSNumber(value: value)
    }

    static func double(_ array: MLMultiArray, offset: Int, label: String) throws -> Double {
        try validateOffset(offset, in: array, label: label)
        return array[offset].doubleValue
    }

    private static func validateOffset(_ offset: Int, in array: MLMultiArray, label: String) throws {
        guard offset >= 0 && offset < array.count else {
            let actualShape = shape(array)
            let actualStrides = strides(array)
            print("""
            MLMultiArray offset out of bounds [\(label)]
              shape=\(actualShape)
              strides=\(actualStrides)
              count=\(array.count)
              requested_offset=\(offset)
            """)
            throw CoreMLMultiArrayIndexingError.offsetOutOfBounds(
                label: label,
                offset: offset,
                count: array.count,
                shape: actualShape,
                strides: actualStrides
            )
        }
    }

    private static func shape(_ array: MLMultiArray) -> [Int] {
        array.shape.map { $0.intValue }
    }

    private static func strides(_ array: MLMultiArray) -> [Int] {
        array.strides.map { $0.intValue }
    }
}

/// The RTMPose-s checkpoint the app runs (the replay tools too, unless given `--model`).
/// Both mlpackages ship in the bundle, so switching is this one value.
/// Still `.coco17`: on the same footage Halpe26 changed a squat rep count (1 → 2 on
/// squat_03) and a calibration capture (guided dummy_03 finishes instead of missing
/// leftfront), so it needs a decision before it ships.
enum RTMPoseModel: String, CaseIterable {
    case coco17 = "rtmpose_s_forward"
    case halpe26 = "rtmpose_s_halpe26_forward"

    static let active: RTMPoseModel = .coco17
}

/// Halpe26 indices, from MMPose configs/_base_/datasets/halpe26.py. 0–16 are COCO17 in the
/// same order; 17 head, 18 neck, 19 hip are deliberately unused (MotionAGFormer keeps its
/// own synthetic pelvis/neck/head).
enum Halpe26 {
    static let jointCount = 26
    static let leftBigToe = 20
    static let rightBigToe = 21
    static let leftSmallToe = 22
    static let rightSmallToe = 23
    static let leftHeel = 24
    static let rightHeel = 25
}

/// Halpe26 foot keypoints in the same coordinate space as the COCO17 array beside them.
struct FootKeypoints {
    let leftBigToe: PoseKeypoint
    let rightBigToe: PoseKeypoint
    let leftSmallToe: PoseKeypoint
    let rightSmallToe: PoseKeypoint
    let leftHeel: PoseKeypoint
    let rightHeel: PoseKeypoint
}

struct SimCCDecodeResult {
    /// COCO17 joints (the first 17 of either model) — the only thing evaluators,
    /// calibration and MotionAGFormer see.
    let inputCoordinates: [PosePoint]
    let confidences: [Double]
    /// Halpe26 joints 17–25 in input coordinates; empty for the COCO17 model.
    let extraInputCoordinates: [PosePoint]
    let extraConfidences: [Double]
}

enum SimCCDecoderError: Error {
    case invalidShape(String)
}

enum SimCCDecoder {
    static let cocoJointCount = 17
    static let xBinCount = 384
    static let yBinCount = 512

    static func decodeToInputCoordinates(
        simccX: MLMultiArray,
        simccY: MLMultiArray,
        splitRatio: Double = PoseCoordinateTransforms.simccSplitRatio
    ) throws -> SimCCDecodeResult {
        // 17 (COCO17 model) or 26 (Halpe26 model); anything else fails the shape check below.
        let jointCount = simccX.shape.count == 3 && simccX.shape[1].intValue == Halpe26.jointCount
            ? Halpe26.jointCount : cocoJointCount
        try CoreMLMultiArrayIndexing.validateShape(
            simccX,
            expectedShape: [1, jointCount, xBinCount],
            label: "SimCCDecoder.simcc_x"
        )
        try CoreMLMultiArrayIndexing.validateShape(
            simccY,
            expectedShape: [1, jointCount, yBinCount],
            label: "SimCCDecoder.simcc_y"
        )

        var coordinates: [PosePoint] = []
        var confidences: [Double] = []
        coordinates.reserveCapacity(jointCount)
        confidences.reserveCapacity(jointCount)

        for jointIndex in 0..<jointCount {
            let xResult = try argmaxSimCCX(array: simccX, jointIndex: jointIndex)
            let yResult = try argmaxSimCCY(array: simccY, jointIndex: jointIndex)
            let confidence = min(xResult.value, yResult.value)

            if confidence <= 0.0 {
                coordinates.append(PosePoint(x: -1.0 / splitRatio, y: -1.0 / splitRatio))
            } else {
                coordinates.append(PosePoint(
                    x: Double(xResult.index) / splitRatio,
                    y: Double(yResult.index) / splitRatio
                ))
            }
            confidences.append(confidence)
        }

        return SimCCDecodeResult(
            inputCoordinates: Array(coordinates[..<cocoJointCount]),
            confidences: Array(confidences[..<cocoJointCount]),
            extraInputCoordinates: Array(coordinates[cocoJointCount...]),
            extraConfidences: Array(confidences[cocoJointCount...])
        )
    }

    private static func argmaxSimCCX(
        array: MLMultiArray,
        jointIndex: Int
    ) throws -> (index: Int, value: Double) {
        var bestIndex = 0
        var bestValue = -Double.greatestFiniteMagnitude
        for binIndex in 0..<xBinCount {
            let offset = CoreMLMultiArrayIndexing.simccXOffset(joint: jointIndex, xIndex: binIndex)
            let value = try CoreMLMultiArrayIndexing.double(
                array,
                offset: offset,
                label: "SimCCDecoder.simcc_x"
            )
            if value > bestValue {
                bestValue = value
                bestIndex = binIndex
            }
        }
        return (bestIndex, bestValue)
    }

    private static func argmaxSimCCY(
        array: MLMultiArray,
        jointIndex: Int
    ) throws -> (index: Int, value: Double) {
        var bestIndex = 0
        var bestValue = -Double.greatestFiniteMagnitude
        for binIndex in 0..<yBinCount {
            let offset = CoreMLMultiArrayIndexing.simccYOffset(joint: jointIndex, yIndex: binIndex)
            let value = try CoreMLMultiArrayIndexing.double(
                array,
                offset: offset,
                label: "SimCCDecoder.simcc_y"
            )
            if value > bestValue {
                bestValue = value
                bestIndex = binIndex
            }
        }
        return (bestIndex, bestValue)
    }
}
