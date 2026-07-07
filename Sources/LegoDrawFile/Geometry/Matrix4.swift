/// The 3x3 rotation/scale + translation transform used by LDraw type-1 (subfile reference) lines:
/// ```
/// a b c x
/// d e f y
/// g h i z
/// 0 0 0 1
/// ```
public struct Matrix4: Sendable, Equatable {
    public var a: Float
    public var b: Float
    public var c: Float
    public var d: Float
    public var e: Float
    public var f: Float
    public var g: Float
    public var h: Float
    public var i: Float
    public var x: Float
    public var y: Float
    public var z: Float

    public init(
        a: Float, b: Float, c: Float, x: Float,
        d: Float, e: Float, f: Float, y: Float,
        g: Float, h: Float, i: Float, z: Float
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.e = e
        self.f = f
        self.g = g
        self.h = h
        self.i = i
        self.x = x
        self.y = y
        self.z = z
    }
}

extension Matrix4 {

    public static let identity = Matrix4(
        a: 1, b: 0, c: 0, x: 0,
        d: 0, e: 1, f: 0, y: 0,
        g: 0, h: 0, i: 1, z: 0
    )

    /// Composes two transforms such that applying the result is equivalent to
    /// applying `self` first, then `other` (`other * self` in row-vector convention,
    /// matching LDraw's traversal where a subfile's own transform is applied within
    /// the coordinate space established by its parent).
    public func multiplied(by other: Matrix4) -> Matrix4 {
        Matrix4(
            a: other.a * a + other.b * d + other.c * g,
            b: other.a * b + other.b * e + other.c * h,
            c: other.a * c + other.b * f + other.c * i,
            x: other.a * x + other.b * y + other.c * z + other.x,
            d: other.d * a + other.e * d + other.f * g,
            e: other.d * b + other.e * e + other.f * h,
            f: other.d * c + other.e * f + other.f * i,
            y: other.d * x + other.e * y + other.f * z + other.y,
            g: other.g * a + other.h * d + other.i * g,
            h: other.g * b + other.h * e + other.i * h,
            i: other.g * c + other.h * f + other.i * i,
            z: other.g * x + other.h * y + other.i * z + other.z
        )
    }

    public func transformingPoint(_ v: Vector3) -> Vector3 {
        Vector3(
            x: a * v.x + b * v.y + c * v.z + x,
            y: d * v.x + e * v.y + f * v.z + y,
            z: g * v.x + h * v.y + i * v.z + z
        )
    }

    public func transformingDirection(_ v: Vector3) -> Vector3 {
        Vector3(
            x: a * v.x + b * v.y + c * v.z,
            y: d * v.x + e * v.y + f * v.z,
            z: g * v.x + h * v.y + i * v.z
        )
    }

    /// The determinant of the 3x3 rotation/scale block. A negative determinant
    /// (e.g. from a mirrored/negative-scale subfile instance) flips the effective
    /// BFC winding of the geometry it contains.
    public var determinant: Float {
        a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    }
}
