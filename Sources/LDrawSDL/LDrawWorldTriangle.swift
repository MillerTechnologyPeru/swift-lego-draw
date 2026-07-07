import LegoDrawFile

/// A single triangle in world space, with its color already resolved — the flattened
/// unit of work for the SDL painter's-algorithm renderer.
public struct LDrawWorldTriangle: Sendable {
    public var vertex1: Vector3
    public var vertex2: Vector3
    public var vertex3: Vector3
    public var color: LDrawResolvedColor

    public init(vertex1: Vector3, vertex2: Vector3, vertex3: Vector3, color: LDrawResolvedColor) {
        self.vertex1 = vertex1
        self.vertex2 = vertex2
        self.vertex3 = vertex3
        self.color = color
    }

    /// The face normal, computed from vertex winding (right-hand rule).
    public var normal: Vector3 {
        (vertex2 - vertex1).cross(vertex3 - vertex1).normalized
    }

    public var centroid: Vector3 {
        (vertex1 + vertex2 + vertex3) * (1.0 / 3.0)
    }
}
