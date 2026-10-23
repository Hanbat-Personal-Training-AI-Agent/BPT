import Foundation
import simd
import XCTest
@testable import CalibrationEngineKit

/// All inputs are procedural boxes; no captured/user geometry or binary fixtures.
final class GLBMeshTests: XCTestCase {
    private func box(indexType: Int = 5125, scale: Float = 1, zUp: Bool = false,
                     normals: Bool = false, change: ((inout [String: Any]) -> Void)? = nil) throws -> Data {
        func word(_ value: UInt32) -> [UInt8] {
            (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        }
        let corners: [SIMD3<Float>] = [
            SIMD3(-0.5, -1, -0.5), SIMD3(0.5, -1, -0.5),
            SIMD3(0.5, 1, -0.5), SIMD3(-0.5, 1, -0.5),
            SIMD3(-0.5, -1, 0.5), SIMD3(0.5, -1, 0.5),
            SIMD3(0.5, 1, 0.5), SIMD3(-0.5, 1, 0.5),
        ]
        let triangles: [UInt32] = [0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7,
                                   0, 1, 5, 0, 5, 4, 3, 7, 6, 3, 6, 2,
                                   0, 4, 7, 0, 7, 3, 1, 2, 6, 1, 6, 5]
        var bin = [UInt8](repeating: 0, count: 12)  // view offset 8 + accessor offset 4
        for index in triangles { bin += word(index).prefix(indexType == 5123 ? 2 : 4) }
        let indexLength = bin.count - 8
        let vertexOffset = bin.count
        bin += [0, 0, 0, 0]  // POSITION accessor offset
        for corner in corners {
            let p = (zUp ? SIMD3(corner.x, -corner.z, corner.y) : corner) * scale + SIMD3(12, 8, -7) * scale
            for value in [p.x, p.y, p.z] { bin += word(value.bitPattern) }
            if normals {
                let n = simd_normalize(zUp ? SIMD3(corner.x, -corner.z, corner.y) : corner)
                for value in [n.x, n.y, n.z] { bin += word(value.bitPattern) }
            } else {
                bin += [0, 0, 0, 0]  // byteStride includes unused bytes
            }
        }
        var accessors: [[String: Any]] = [
            ["bufferView": 0, "byteOffset": 4, "componentType": indexType, "count": 36, "type": "SCALAR"],
            ["bufferView": 1, "byteOffset": 4, "componentType": 5126, "count": 8, "type": "VEC3"],
        ]
        var attributes = ["POSITION": 1]
        if normals {
            accessors.append(["bufferView": 1, "byteOffset": 16, "componentType": 5126, "count": 8, "type": "VEC3"])
            attributes["NORMAL"] = 2
        }
        var json: [String: Any] = [
            "asset": ["version": "2.0"], "buffers": [["byteLength": bin.count]],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 8, "byteLength": indexLength],
                ["buffer": 0, "byteOffset": vertexOffset, "byteLength": bin.count - vertexOffset, "byteStride": normals ? 24 : 16],
            ],
            "accessors": accessors,
            "meshes": [["primitives": [["attributes": attributes, "indices": 0, "mode": 4]]]],
        ]
        change?(&json)
        var header = [UInt8](try JSONSerialization.data(withJSONObject: json))
        while header.count % 4 != 0 { header.append(0x20) }
        return Data(word(0x4654_6C67) + word(2) + word(UInt32(28 + header.count + bin.count)) +
                    word(UInt32(header.count)) + word(0x4E4F_534A) + header +
                    word(UInt32(bin.count)) + word(0x004E_4942) + bin)
    }

    func testLittleEndianIndicesOffsetsStrideAndMultipleViews() throws {
        for type in [5123, 5125] {
            let mesh = try GLBMesh(data: box(indexType: type))
            XCTAssertEqual(mesh.positions.count, 8)
            XCTAssertEqual(mesh.indices.count, 36)
            XCTAssertEqual(mesh.indices.prefix(3), [0, 2, 1])
            XCTAssertEqual(mesh.bounds.min.y, 7, accuracy: 1e-6)
            XCTAssertEqual(mesh.bounds.max.y, 9, accuracy: 1e-6)
            for (p, n) in zip(mesh.positions, mesh.normals) {
                XCTAssertEqual(simd_length(n), 1, accuracy: 1e-5)
                XCTAssertGreaterThan(simd_dot(n, p - SIMD3(12, 8, -7)), 0)
            }
        }
    }

    func testReadsInterleavedNormals() throws {
        let mesh = try GLBMesh(data: box(normals: true))
        for (p, n) in zip(mesh.positions, mesh.normals) {
            XCTAssertLessThan(simd_distance(n, simd_normalize(p - SIMD3(12, 8, -7))), 1e-5)
        }
    }

    func testCentresMetresAndCentimetresWithEitherUpAxis() throws {
        for scale: Float in [1, 100] {
            for zUp in [false, true] {
                let mesh = try GLBMesh(data: box(scale: scale, zUp: zUp)).centeredYUp()
                XCTAssertEqual(mesh.bounds.min.y, -0.5, accuracy: 1e-5)
                XCTAssertEqual(mesh.bounds.max.y, 0.5, accuracy: 1e-5)
                XCTAssertLessThan(simd_length(mesh.bounds.min + mesh.bounds.max), 1e-5)
                for (p, n) in zip(mesh.positions, mesh.normals) { XCTAssertGreaterThan(simd_dot(p, n), 0) }
                let radius = simd_length(mesh.bounds.max)
                for aspect: Float in [0.4, 1, 2] {
                    let distance = GLBMesh.cameraDistance(radius: radius, aspect: aspect)
                    let vertical = Float(35) * .pi / 360
                    let halfFov = min(vertical, atan(tan(vertical) * aspect))
                    XCTAssertGreaterThan(distance * sin(halfFov), radius)
                }
            }
        }
    }

    func testRejectsTruncatedOrForeignData() throws {
        let data = try box()
        XCTAssertThrowsError(try GLBMesh(data: data.prefix(data.count - 10)))
        XCTAssertThrowsError(try GLBMesh(data: Data("not a glb".utf8)))
    }

    func testRejectsAccessorEscapingItsViewEvenInsideBIN() throws {
        let data = try box { json in
            var views = json["bufferViews"] as! [[String: Any]]
            views[0]["byteLength"] = 12
            json["bufferViews"] = views
        }
        XCTAssertThrowsError(try GLBMesh(data: data))
    }

    func testRejectsNegativeOffsetsSmallStrideAndHugeCount() throws {
        for (key, value) in [("byteOffset", -4), ("count", Int.max)] {
            let data = try box { json in
                var accessors = json["accessors"] as! [[String: Any]]
                accessors[1][key] = value
                json["accessors"] = accessors
            }
            XCTAssertThrowsError(try GLBMesh(data: data))
        }
        let data = try box { json in
            var views = json["bufferViews"] as! [[String: Any]]
            views[1]["byteStride"] = 4
            json["bufferViews"] = views
        }
        XCTAssertThrowsError(try GLBMesh(data: data))
    }
}
