import Foundation
import simd

/// The one triangle mesh in a binary glTF (the server's `body.glb`: SMPL, metres, y up, feet on
/// y = 0), with smooth vertex normals. SceneKit cannot read glTF, and this is all the reveal needs.
struct GLBMesh {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var indices: [UInt32]

    enum Failure: Error { case format(String) }

    init(data: Data) throws {
        let bytes = [UInt8](data)
        func u32(_ at: Int) throws -> Int {
            guard at >= 0, at + 4 <= bytes.count else { throw Failure.format("truncated") }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        guard bytes.count >= 20, try u32(0) == 0x4654_6C67, try u32(4) == 2 else { throw Failure.format("not glTF 2") }
        // Chunks: JSON first, then BIN.
        let jsonLength = try u32(12)
        guard try u32(16) == 0x4E4F_534A, 20 + jsonLength <= bytes.count else { throw Failure.format("no JSON chunk") }
        let binStart = 20 + jsonLength + 8
        guard binStart <= bytes.count, try u32(binStart - 4) == 0x004E_4942 else { throw Failure.format("no BIN chunk") }
        let binLength = try u32(binStart - 8)
        guard binStart + binLength <= bytes.count else { throw Failure.format("truncated BIN") }
        guard let json = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<20 + jsonLength)) as? [String: Any],
              let accessors = json["accessors"] as? [[String: Any]],
              let views = json["bufferViews"] as? [[String: Any]],
              let primitive = ((json["meshes"] as? [[String: Any]])?.first?["primitives"] as? [[String: Any]])?.first,
              let positionIndex = (primitive["attributes"] as? [String: Any])?["POSITION"] as? Int
        else { throw Failure.format("no mesh") }

        /// Reads accessor `index` as `components` numbers per element.
        func read(_ index: Int, components: Int) throws -> [Float] {
            guard accessors.indices.contains(index), let viewIndex = accessors[index]["bufferView"] as? Int,
                  views.indices.contains(viewIndex), let count = accessors[index]["count"] as? Int,
                  let type = accessors[index]["componentType"] as? Int
            else { throw Failure.format("bad accessor") }
            let size: Int
            switch type {
            case 5121: size = 1  // UNSIGNED_BYTE
            case 5123: size = 2  // UNSIGNED_SHORT
            case 5125, 5126: size = 4  // UNSIGNED_INT, FLOAT
            default: throw Failure.format("component type \(type)")
            }
            let view = views[viewIndex]
            let stride = (view["byteStride"] as? Int) ?? size * components
            let start = binStart + ((view["byteOffset"] as? Int) ?? 0) + ((accessors[index]["byteOffset"] as? Int) ?? 0)
            guard count >= 0, count == 0 || start + (count - 1) * stride + size * components <= binStart + binLength
            else { throw Failure.format("accessor out of range") }
            var out = [Float]()
            out.reserveCapacity(count * components)
            for element in 0..<count {
                for c in 0..<components {
                    let at = start + element * stride + c * size
                    switch type {
                    case 5126: out.append(Float(bitPattern: UInt32(try u32(at))))
                    case 5125: out.append(Float(try u32(at)))
                    case 5123: out.append(Float(Int(bytes[at]) | Int(bytes[at + 1]) << 8))
                    default: out.append(Float(bytes[at]))
                    }
                }
            }
            return out
        }

        let flat = try read(positionIndex, components: 3)
        let positions = stride(from: 0, to: flat.count, by: 3).map { SIMD3(flat[$0], flat[$0 + 1], flat[$0 + 2]) }
        let indices: [UInt32]
        if let indexAccessor = primitive["indices"] as? Int {
            // Float holds every index below 2^24; SMPL has 6,890 vertices.
            indices = try read(indexAccessor, components: 1).map { UInt32($0) }
        } else {
            indices = (0..<UInt32(positions.count)).map { $0 }
        }
        guard !positions.isEmpty, indices.count % 3 == 0, indices.allSatisfy({ Int($0) < positions.count })
        else { throw Failure.format("bad triangles") }

        // Area-weighted smooth normals (the server's GLB has none).
        var sums = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let (a, b, c) = (Int(indices[t]), Int(indices[t + 1]), Int(indices[t + 2]))
            let n = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            sums[a] += n; sums[b] += n; sums[c] += n
        }
        normals = sums.map { simd_length($0) > 0 ? simd_normalize($0) : SIMD3(0, 1, 0) }
        self.positions = positions
        self.indices = indices
    }

    /// Lowest and highest y (the mesh's standing height range).
    var yRange: ClosedRange<Float> {
        let ys = positions.map(\.y)
        return ys.min()!...ys.max()!
    }
}
