/// A line-type-1 statement: a reference to another file (a part, primitive, or submodel)
/// placed via a color and a transform.
public struct LDrawSubfileReference: Sendable, Equatable {
    public var color: LDrawColorReference
    public var transform: Matrix4
    /// The referenced file name, exactly as written (rest-of-line, case preserved).
    public var fileName: String

    public init(color: LDrawColorReference, transform: Matrix4, fileName: String) {
        self.color = color
        self.transform = transform
        self.fileName = fileName
    }
}
