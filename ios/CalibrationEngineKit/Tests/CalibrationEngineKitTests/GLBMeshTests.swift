import Foundation
import simd
import XCTest
@testable import CalibrationEngineKit

/// The body-mesh reveal reads the server's GLB (trimesh export, uint32 indices, no normals).
final class GLBMeshTests: XCTestCase {
    /// trimesh.creation.box(extents=(1, 2, 1)) lifted to y = 0...2, exported like server/calibration_modal/body.glb.
    private let box = Data(base64Encoded: "Z2xURgIAAACcAwAAkAIAAEpTT057InNjZW5lIjowLCJzY2VuZXMiOlt7Im5vZGVzIjpbMF19XSwiYXNzZXQiOnsidmVyc2lvbiI6IjIuMCIsImdlbmVyYXRvciI6Imh0dHBzOi8vZ2l0aHViLmNvbS9taWtlZGgvdHJpbWVzaCJ9LCJhY2Nlc3NvcnMiOlt7ImNvbXBvbmVudFR5cGUiOjUxMjUsInR5cGUiOiJTQ0FMQVIiLCJidWZmZXJWaWV3IjowLCJjb3VudCI6MzYsIm1heCI6WzddLCJtaW4iOlswXX0seyJjb21wb25lbnRUeXBlIjo1MTI2LCJ0eXBlIjoiVkVDMyIsImJ5dGVPZmZzZXQiOjAsImJ1ZmZlclZpZXciOjEsImNvdW50Ijo4LCJtYXgiOlswLjUsMi4wLDAuNV0sIm1pbiI6Wy0wLjUsMC4wLC0wLjVdfV0sIm1lc2hlcyI6W3sibmFtZSI6Imdlb21ldHJ5XzAiLCJleHRyYXMiOnsic2hhcGUiOiJib3giLCJleHRlbnRzIjpbMS4wLDIuMCwxLjBdfSwicHJpbWl0aXZlcyI6W3siYXR0cmlidXRlcyI6eyJQT1NJVElPTiI6MX0sImluZGljZXMiOjAsIm1vZGUiOjR9XX1dLCJub2RlcyI6W3sibmFtZSI6Imdlb21ldHJ5XzAiLCJtZXNoIjowfV0sImJ1ZmZlcnMiOlt7ImJ5dGVMZW5ndGgiOjI0MH1dLCJidWZmZXJWaWV3cyI6W3siYnVmZmVyIjowLCJieXRlT2Zmc2V0IjowLCJieXRlTGVuZ3RoIjoxNDR9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0IjoxNDQsImJ5dGVMZW5ndGgiOjk2fV19IPAAAABCSU4AAQAAAAMAAAAAAAAABAAAAAEAAAAAAAAAAAAAAAMAAAACAAAAAgAAAAQAAAAAAAAAAQAAAAcAAAADAAAABQAAAAEAAAAEAAAABQAAAAcAAAABAAAAAwAAAAcAAAACAAAABgAAAAQAAAACAAAAAgAAAAcAAAAGAAAABgAAAAUAAAAEAAAABwAAAAUAAAAGAAAAAAAAvwAAAAAAAAC/AAAAvwAAAAAAAAA/AAAAvwAAAEAAAAC/AAAAvwAAAEAAAAA/AAAAPwAAAAAAAAC/AAAAPwAAAAAAAAA/AAAAPwAAAEAAAAC/AAAAPwAAAEAAAAA/")!

    func testReadsTrimeshGLB() throws {
        let mesh = try GLBMesh(data: box)
        XCTAssertEqual(mesh.positions.count, 8)
        XCTAssertEqual(mesh.indices.count, 36)
        XCTAssertEqual(mesh.yRange.lowerBound, 0, accuracy: 1e-6)
        XCTAssertEqual(mesh.yRange.upperBound, 2, accuracy: 1e-6)
        let centre = SIMD3<Float>(0, 1, 0)
        for (p, n) in zip(mesh.positions, mesh.normals) {
            XCTAssertEqual(simd_length(n), 1, accuracy: 1e-5)
            XCTAssertGreaterThan(simd_dot(n, p - centre), 0, "normals point outward")
        }
    }

    func testRejectsTruncatedOrForeignData() {
        XCTAssertThrowsError(try GLBMesh(data: box.prefix(box.count - 10)))
        XCTAssertThrowsError(try GLBMesh(data: Data("not a glb at all, just text".utf8)))
    }
}
