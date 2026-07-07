/// A line-type-2 statement: a single line segment, typically used for edges.
public struct LDrawLine: Sendable, Equatable {
    public var color: LDrawColorReference
    public var start: Vector3
    public var end: Vector3

    public init(color: LDrawColorReference, start: Vector3, end: Vector3) {
        self.color = color
        self.start = start
        self.end = end
    }
}
