#if os(Linux)
import LegoDrawFile

/// A single tightly-packed vertex for the Vulkan vertex buffer.
/// Layout: position (3×Float @ 0), normal (3×Float @ 12), color (4×Float @ 24).
/// Must match the `layout(location = ...)` bindings in `triangle.vert`.
public struct LDrawVulkanVertex: Sendable {
    public var px, py, pz: Float
    public var nx, ny, nz: Float
    public var r, g, b, a: Float

    public init(px: Float, py: Float, pz: Float,
                nx: Float, ny: Float, nz: Float,
                r: Float, g: Float, b: Float, a: Float) {
        self.px = px; self.py = py; self.pz = pz
        self.nx = nx; self.ny = ny; self.nz = nz
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}
#endif
