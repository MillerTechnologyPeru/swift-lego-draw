/// A line-type-3 statement: a filled triangle.
public struct LDrawTriangle: Sendable, Equatable {
    public var color: LDrawColorReference
    public var vertex1: Vector3
    public var vertex2: Vector3
    public var vertex3: Vector3

    public init(color: LDrawColorReference, vertex1: Vector3, vertex2: Vector3, vertex3: Vector3) {
        self.color = color
        self.vertex1 = vertex1
        self.vertex2 = vertex2
        self.vertex3 = vertex3
    }
}
