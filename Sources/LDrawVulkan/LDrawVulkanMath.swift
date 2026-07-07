#if os(Linux)
import Glibc
import LegoDrawFile

/// Column-major 4×4 float matrix matching GLSL's `mat4` memory layout —
/// used instead of `simd.float4x4` (Apple-only) for the Vulkan renderer.
struct Mat4 {
    /// 16 elements, column-major: `m[col * 4 + row]`.
    var m: [Float]

    static let identity = Mat4(m: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    ])

    static func * (lhs: Mat4, rhs: Mat4) -> Mat4 {
        var out = [Float](repeating: 0, count: 16)
        for col in 0..<4 {
            for row in 0..<4 {
                var sum: Float = 0
                for k in 0..<4 {
                    sum += lhs.m[k * 4 + row] * rhs.m[col * 4 + k]
                }
                out[col * 4 + row] = sum
            }
        }
        return Mat4(m: out)
    }
}

func lookAt(eye: Vector3, center: Vector3, up: Vector3) -> Mat4 {
    let f = (center - eye).normalized
    let r = f.cross(up).normalized
    let u = r.cross(f)
    return Mat4(m: [
        r.x, u.x, -f.x, 0,
        r.y, u.y, -f.y, 0,
        r.z, u.z, -f.z, 0,
        -r.dot(eye), -u.dot(eye), f.dot(eye), 1
    ])
}

/// Vulkan clip space has Y pointing down and Z in [0, 1] (unlike OpenGL's
/// [-1, 1]), so this differs from a standard GL perspective matrix.
func perspectiveVulkan(fovY: Float, aspect: Float, near: Float, far: Float) -> Mat4 {
    let f = 1 / tan(fovY * 0.5)
    return Mat4(m: [
        f / aspect, 0,  0,                          0,
        0,         -f,  0,                          0,
        0,          0,  far / (near - far),        -1,
        0,          0,  (far * near) / (near - far), 0
    ])
}
#endif
