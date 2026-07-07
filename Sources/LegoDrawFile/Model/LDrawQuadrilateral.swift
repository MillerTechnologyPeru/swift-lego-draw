/// A line-type-4 statement: a filled quadrilateral.
///
/// Kept as a quad rather than pre-triangulated, since LDraw's BFC (planarity and
/// winding) semantics are defined in terms of the quad as written.
public struct LDrawQuadrilateral: Sendable, Equatable {
    public var color: LDrawColorReference
    public var vertex1: Vector3
    public var vertex2: Vector3
    public var vertex3: Vector3
    public var vertex4: Vector3

    public init(
        color: LDrawColorReference,
        vertex1: Vector3, vertex2: Vector3, vertex3: Vector3, vertex4: Vector3
    ) {
        self.color = color
        self.vertex1 = vertex1
        self.vertex2 = vertex2
        self.vertex3 = vertex3
        self.vertex4 = vertex4
    }
}
