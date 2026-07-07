/// The result of ``LDrawParser/parseAuto(_:)``, distinguishing a plain single-file
/// document from a multi-part (MPD) one.
public enum LDrawParseResult: Sendable {
    case singleFile(LDrawSourceFile)
    case multiPartDocument(LDrawMultiPartDocument)
}
