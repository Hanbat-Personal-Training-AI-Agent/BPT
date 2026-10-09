import CoreML
import XCTest
@testable import CalibrationEngineKit

final class RTMPoseWorkspaceTests: XCTestCase {
    private func fill(_ workspace: RTMPoseInputWorkspace, seed: Int) throws {
        for i in workspace.pixels.indices { workspace.pixels[i] = UInt8((i * 13 + seed) % 256) }
        try PosePreprocess.normalizeRGBAIntoRTMPoseInput(workspace.pixels, input: workspace.input, width: 192, height: 256)
    }

    func testWorkspaceOverwritesAllChannelsWithoutReallocatingInput() throws {
        let workspace = try RTMPoseInputWorkspace()
        let pointer = workspace.input.dataPointer
        let pixelPointer = workspace.pixels.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        for seed in [0, 59, 217] {
            try fill(workspace, seed: seed)
            let fresh = try PosePreprocess.makeRTMPoseInputArray()
            try PosePreprocess.normalizeRGBAIntoRTMPoseInput(workspace.pixels, input: fresh, width: 192, height: 256)
            XCTAssertEqual(workspace.input.dataPointer, pointer)
            XCTAssertEqual(workspace.pixels.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, pixelPointer)
            XCTAssertTrue(workspace.provider.featureValue(for: "input_image")!.multiArrayValue === workspace.input)
            let reusedValues = workspace.input.dataPointer.assumingMemoryBound(to: Float.self)
            let freshValues = fresh.dataPointer.assumingMemoryBound(to: Float.self)
            for index in 0..<fresh.count { XCTAssertEqual(reusedValues[index], freshValues[index]) }
        }
    }

    func testCoreMLPredictionParityWithFreshProviderAcrossFrames() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let package = root.appendingPathComponent("ios/Runner/NativePose/Models/\(RTMPoseModel.active.rawValue).mlpackage")
        guard FileManager.default.fileExists(atPath: package.path) else {
            throw XCTSkip("Local RTMPose model absent; tensor parity is still tested")
        }
        let compiled = try MLModel.compileModel(at: package)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: compiled, configuration: config)
        let reused = try RTMPoseInputWorkspace()
        var previousOutput: [Double]?
        var observedChange = false
        for seed in [0, 59, 217] {
            try fill(reused, seed: seed)
            let fresh = try RTMPoseInputWorkspace()
            try fill(fresh, seed: seed)
            let actual = try model.prediction(from: reused.provider)
            let expected = try model.prediction(from: fresh.provider)
            var values: [Double] = []
            for name in ["simcc_x", "simcc_y"] {
                let a = try XCTUnwrap(actual.featureValue(for: name)?.multiArrayValue)
                let b = try XCTUnwrap(expected.featureValue(for: name)?.multiArrayValue)
                XCTAssertEqual(a.shape, b.shape)
                for i in 0..<a.count {
                    XCTAssertEqual(a[i].doubleValue, b[i].doubleValue, accuracy: 1e-6)
                    values.append(a[i].doubleValue)
                }
            }
            if let previousOutput, previousOutput != values { observedChange = true }
            previousOutput = values
        }
        XCTAssertTrue(observedChange, "Reused provider must see new pixels, not a cached first frame")
    }

    func testHalpe26DecodeKeepsCOCO17AndSplitsOffFeet() throws {
        let x = try MLMultiArray(shape: [1, 26, 384], dataType: .float32)
        let y = try MLMultiArray(shape: [1, 26, 512], dataType: .float32)
        for i in 0..<x.count { x[i] = 0 }
        for i in 0..<y.count { y[i] = 0 }
        // joint j peaks at x bin 10+j, y bin 100+j
        for j in 0..<26 {
            x[j * 384 + 10 + j] = 0.9
            y[j * 512 + 100 + j] = 0.8
        }
        let decoded = try SimCCDecoder.decodeToInputCoordinates(simccX: x, simccY: y)
        XCTAssertEqual(decoded.inputCoordinates.count, 17)
        XCTAssertEqual(decoded.extraInputCoordinates.count, 9)
        XCTAssertEqual(decoded.inputCoordinates[16].x, Double(10 + 16) / 2)
        let feet = try XCTUnwrap(PoseCoordinateTransforms.applyInverseAffineToFeet(
            decoded: decoded, inverseAffine: Affine2x3(a: 2, b: 0, c: 0, d: 0, e: 2, f: 0)))
        XCTAssertEqual(feet.rightHeel.x, Double(10 + Halpe26.rightHeel))
        XCTAssertEqual(feet.leftBigToe.y, Double(100 + Halpe26.leftBigToe))
        XCTAssertEqual(feet.leftHeel.confidence, 0.8, accuracy: 1e-6)
        XCTAssertNil(PoseCoordinateTransforms.applyInverseAffineToFeet(
            decoded: SimCCDecodeResult(inputCoordinates: [], confidences: [],
                                       extraInputCoordinates: [], extraConfidences: []),
            inverseAffine: Affine2x3(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0)))
    }
}
