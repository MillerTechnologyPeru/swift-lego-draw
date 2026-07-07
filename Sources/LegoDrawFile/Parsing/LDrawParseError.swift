/// An error produced while parsing LDraw statement text.
///
/// Declared as a concrete `Error`-conforming enum (rather than relying on `any Error`)
/// so that parsing entry points can use typed throws (`throws(LDrawParseError)`),
/// avoiding existential error boxing that is unfriendly to Embedded Swift.
public enum LDrawParseError: Error, Sendable, Equatable {
    case malformedLine(lineNumber: Int, content: String)
    case unknownLineType(lineNumber: Int, type: String)
    case wrongFieldCount(lineNumber: Int, expected: Int, found: Int)
    case invalidNumber(lineNumber: Int, field: String)
    case invalidColorReference(lineNumber: Int, field: String)
    case unterminatedFileSection(fileName: String)
    case unexpectedNoFile(lineNumber: Int)
}
