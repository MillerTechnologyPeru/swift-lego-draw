import SceneKit
import simd
import LegoDrawFile

extension SCNVector3 {
    init(_ v: Vector3) {
        self.init(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z))
    }
}

extension SCNMatrix4 {
    /// Converts LDraw's row-vector transform (`a b c x / d e f y / g h i z`) into
    /// SceneKit's row-major `SCNMatrix4` (translation in `m41`/`m42`/`m43`).
    init(_ m: Matrix4) {
        self.init(
            m11: CGFloat(m.a), m12: CGFloat(m.d), m13: CGFloat(m.g), m14: 0,
            m21: CGFloat(m.b), m22: CGFloat(m.e), m23: CGFloat(m.h), m24: 0,
            m31: CGFloat(m.c), m32: CGFloat(m.f), m33: CGFloat(m.i), m34: 0,
            m41: CGFloat(m.x), m42: CGFloat(m.y), m43: CGFloat(m.z), m44: 1
        )
    }
}

extension simd_float4x4 {
    /// Column-major conversion matching `Matrix4.transformingPoint`'s row-times-column
    /// convention (`p' = M * p` for a column vector `p`).
    init(_ m: Matrix4) {
        self.init(
            simd_float4(m.a, m.d, m.g, 0),
            simd_float4(m.b, m.e, m.h, 0),
            simd_float4(m.c, m.f, m.i, 0),
            simd_float4(m.x, m.y, m.z, 1)
        )
    }
}
