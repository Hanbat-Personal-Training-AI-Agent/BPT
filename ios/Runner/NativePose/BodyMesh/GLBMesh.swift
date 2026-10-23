import Foundation
import simd

/// The single triangle mesh in the server's binary glTF, with smooth normals.
struct GLBMesh {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var indices: [UInt32]

    enum Failure: Error { case format(String) }

    init(data: Data) throws {
        let bytes = [UInt8](data)
        func u32(_ at: Int) throws -> UInt32 {
            guard at >= 0, at <= bytes.count - 4 else { throw Failure.format("truncated") }
            return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        guard bytes.count >= 28, try u32(0) == 0x4654_6C67, try u32(4) == 2,
              try Int(u32(8)) == bytes.count else { throw Failure.format("not glTF 2") }
        let jsonLength = Int(try u32(12))
        guard try u32(16) == 0x4E4F_534A, jsonLength % 4 == 0, jsonLength <= bytes.count - 28
        else { throw Failure.format("no JSON chunk") }
        let binStart = 28 + jsonLength
        let binLength = Int(try u32(binStart - 8))
        guard try u32(binStart - 4) == 0x004E_4942, binLength <= bytes.count - binStart
        else { throw Failure.format("truncated BIN") }
        guard let json = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<20 + jsonLength)) as? [String: Any],
              let buffers = json["buffers"] as? [[String: Any]], buffers.count == 1,
              buffers[0]["uri"] == nil, let bufferLength = buffers[0]["byteLength"] as? Int,
              bufferLength >= 0, bufferLength <= binLength,
              let accessors = json["accessors"] as? [[String: Any]],
              let views = json["bufferViews"] as? [[String: Any]],
              let meshes = json["meshes"] as? [[String: Any]], meshes.count == 1,
              let primitives = meshes[0]["primitives"] as? [[String: Any]], primitives.count == 1,
              let primitive = primitives.first, (primitive["mode"] as? Int ?? 4) == 4,
              let attributes = primitive["attributes"] as? [String: Any],
              let positionIndex = attributes["POSITION"] as? Int
        else { throw Failure.format("no triangle mesh") }

        // Validate each accessor against its own buffer view, including interleaving.
        func layout(_ index: Int, vector: Bool) throws -> (start: Int, count: Int, stride: Int, type: Int) {
            guard accessors.indices.contains(index) else { throw Failure.format("bad accessor") }
            let accessor = accessors[index]
            guard accessor["sparse"] == nil, (accessor["normalized"] as? Bool ?? false) == false,
                  accessor["type"] as? String == (vector ? "VEC3" : "SCALAR"),
                  let viewIndex = accessor["bufferView"] as? Int, views.indices.contains(viewIndex),
                  let count = accessor["count"] as? Int, count > 0,
                  let type = accessor["componentType"] as? Int,
                  vector ? type == 5126 : [5121, 5123, 5125].contains(type)
            else { throw Failure.format("bad accessor") }
            let view = views[viewIndex]
            let size = type == 5121 ? 1 : (type == 5123 ? 2 : 4)
            let elementSize = size * (vector ? 3 : 1)
            let stride = view["byteStride"] as? Int ?? elementSize
            let viewOffset = view["byteOffset"] as? Int ?? 0
            let offset = accessor["byteOffset"] as? Int ?? 0
            guard view["buffer"] as? Int == 0, let length = view["byteLength"] as? Int,
                  length >= elementSize, viewOffset >= 0, viewOffset <= bufferLength,
                  length <= bufferLength - viewOffset,
                  offset >= 0, offset <= length - elementSize,
                  stride >= elementSize, stride % size == 0,
                  count - 1 <= (length - offset - elementSize) / stride
            else { throw Failure.format("accessor out of range") }
            return (binStart + viewOffset + offset, count, stride, type)
        }
        func vectors(_ index: Int) throws -> [SIMD3<Float>] {
            let layout = try layout(index, vector: true)
            return try (0..<layout.count).map { element in
                let at = layout.start + element * layout.stride
                let v = SIMD3<Float>(Float(bitPattern: try u32(at)), Float(bitPattern: try u32(at + 4)),
                                     Float(bitPattern: try u32(at + 8)))
                guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { throw Failure.format("nonfinite vector") }
                return v
            }
        }
        let positions = try vectors(positionIndex)
        let indices: [UInt32]
        if let indexAccessor = primitive["indices"] as? Int {
            let layout = try layout(indexAccessor, vector: false)
            indices = try (0..<layout.count).map { element in
                let at = layout.start + element * layout.stride
                switch layout.type {
                case 5121: return UInt32(bytes[at])
                case 5123: return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8
                default: return try u32(at)  // Never round uint32 indices through Float.
                }
            }
        } else {
            indices = (0..<UInt32(positions.count)).map { $0 }
        }
        guard !indices.isEmpty, indices.count % 3 == 0, indices.allSatisfy({ Int($0) < positions.count })
        else { throw Failure.format("bad triangles") }

        var sums = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let (a, b, c) = (Int(indices[t]), Int(indices[t + 1]), Int(indices[t + 2]))
            let n = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            sums[a] += n; sums[b] += n; sums[c] += n
        }
        let supplied = try (attributes["NORMAL"] as? Int).map { try vectors($0) }
        guard supplied == nil || supplied?.count == positions.count else { throw Failure.format("bad normals") }
        normals = (supplied ?? sums).map {
            let length = simd_length($0)
            return length.isFinite && length > 0 ? $0 / length : SIMD3(0, 1, 0)
        }
        self.positions = positions
        self.indices = indices
    }

    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        (positions.reduce(positions[0], simd_min), positions.reduce(positions[0], simd_max))
    }

    /// Centre all three axes, rotate the tallest axis up and use a unit-height display mesh.
    /// A right-handed rotation preserves triangle winding and rotates normals identically.
    func centeredYUp() throws -> GLBMesh {
        let box = bounds
        let extent = box.max - box.min
        let height = max(extent.x, max(extent.y, extent.z))
        guard height.isFinite, height > 0 else { throw Failure.format("empty bounds") }
        let centre = box.min / 2 + box.max / 2
        func rotate(_ v: SIMD3<Float>) -> SIMD3<Float> {
            if extent.z > extent.y && extent.z >= extent.x { return SIMD3(v.x, v.z, -v.y) }
            if extent.x > extent.y { return SIMD3(-v.y, v.x, v.z) }
            return v
        }
        var mesh = self
        mesh.positions = positions.map { rotate(($0 - centre) / height) }
        mesh.normals = normals.map(rotate)
        return mesh
    }

    /// A bounding sphere fits through every allowed rotation, even in narrow cards.
    static func cameraDistance(radius: Float, aspect: Float, fieldOfView: Float = 35) -> Float {
        let vertical = fieldOfView * .pi / 360
        let horizontal = atan(tan(vertical) * max(aspect, 0.01))
        return radius * 1.12 / sin(min(vertical, horizontal))
    }
}
