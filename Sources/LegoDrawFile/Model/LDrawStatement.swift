/// A single parsed line of an LDraw file, corresponding to one of the six LDraw line types.
public enum LDrawStatement: Sendable, Equatable {
    /// Line type 0: comment or meta-command.
    case meta(LDrawMetaCommand)
    /// Line type 1: subfile (part/primitive/submodel) reference.
    case subfileReference(LDrawSubfileReference)
    /// Line type 2: line segment.
    case line(LDrawLine)
    /// Line type 3: filled triangle.
    case triangle(LDrawTriangle)
    /// Line type 4: filled quadrilateral.
    case quadrilateral(LDrawQuadrilateral)
    /// Line type 5: optional/conditional line.
    case optionalLine(LDrawOptionalLine)
}
