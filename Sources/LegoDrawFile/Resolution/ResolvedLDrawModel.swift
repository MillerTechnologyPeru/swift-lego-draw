/// A fully-linked LDraw model tree: subfile references have been resolved into
/// nested ``ResolvedLDrawModel`` instances (or a ``Node/missingSubfile`` placeholder),
/// ready for consumers such as `LDrawSceneKit` to walk without further I/O.
public struct ResolvedLDrawModel: Sendable {
    public var name: String?
    /// The BFC state after walking this file's statement stream to completion.
    public var bfcState: LDrawBFCState
    public var children: [Node]

    public init(name: String?, bfcState: LDrawBFCState, children: [Node]) {
        self.name = name
        self.bfcState = bfcState
        self.children = children
    }

    public indirect enum Node: Sendable {
        /// A resolved subfile instance. `invertWinding` folds together the `INVERTNEXT`
        /// BFC directive (if any) that preceded this reference and the sign of the
        /// reference's own transform determinant (a mirrored/negative-scale instance).
        case subfile(transform: Matrix4, color: LDrawColorReference, invertWinding: Bool, model: ResolvedLDrawModel)
        /// A subfile reference that could not be resolved (per `MissingPartPolicy.placeholder`).
        case missingSubfile(transform: Matrix4, color: LDrawColorReference, fileName: String)
        case line(LDrawLine)
        case triangle(LDrawTriangle)
        case quadrilateral(LDrawQuadrilateral)
        case optionalLine(LDrawOptionalLine)
    }
}
