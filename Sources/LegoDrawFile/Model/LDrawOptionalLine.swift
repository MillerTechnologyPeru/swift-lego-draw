/// A line-type-5 statement: a "conditional"/optional line, shown only when the two
/// control points fall on the same side of the viewer's projection of the line
/// (used for smooth-surface edges like cylinders).
public struct LDrawOptionalLine: Sendable, Equatable {
    public var color: LDrawColorReference
    public var start: Vector3
    public var end: Vector3
    public var control1: Vector3
    public var control2: Vector3

    public init(
        color: LDrawColorReference,
        start: Vector3, end: Vector3,
        control1: Vector3, control2: Vector3
    ) {
        self.color = color
        self.start = start
        self.end = end
        self.control1 = control1
        self.control2 = control2
    }
}
