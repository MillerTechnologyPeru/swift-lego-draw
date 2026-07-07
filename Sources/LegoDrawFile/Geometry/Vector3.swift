/// A 3D vector using `Float` coordinates, matching LDraw's coordinate precision.
public struct Vector3: Sendable, Equatable, Hashable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

extension Vector3 {

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static func * (lhs: Vector3, rhs: Float) -> Vector3 {
        Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    public static prefix func - (v: Vector3) -> Vector3 {
        Vector3(x: -v.x, y: -v.y, z: -v.z)
    }

    public func cross(_ other: Vector3) -> Vector3 {
        Vector3(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    public func dot(_ other: Vector3) -> Float {
        x * other.x + y * other.y + z * other.z
    }

    public var length: Float {
        (x * x + y * y + z * z).squareRoot()
    }

    public var normalized: Vector3 {
        let length = self.length
        guard length > 0 else { return .zero }
        return Vector3(x: x / length, y: y / length, z: z / length)
    }
}
