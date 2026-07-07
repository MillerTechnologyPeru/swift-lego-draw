import simd
import LegoDrawFile

/// A single vertex in the flattened Metal vertex buffer.
/// Layout must match the MSL `VertexIn` struct exactly.
public struct LDrawMetalVertex {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var color: SIMD4<Float>

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, color: SIMD4<Float>) {
        self.position = position
        self.normal = normal
        self.color = color
    }
}
