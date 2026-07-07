/// A single parsed logical LDraw file: an ordered statement stream plus header
/// information derived from its leading meta-commands.
///
/// Named `LDrawSourceFile` (rather than `LDrawFile`) to avoid clashing with the
/// `LegoDrawFile` module name.
public struct LDrawSourceFile: Sendable {
    /// The name declared by a `0 FILE` statement (for MPD sections), if any.
    public var name: String?
    public var statements: [LDrawStatement]
    /// The BFC state established by header-level `0 BFC` statements, i.e. those
    /// appearing before the first drawn geometry statement.
    public var initialBFCState: LDrawBFCState
    public var category: String?
    public var keywords: [String]
    /// Parsed from a conventional `0 Author: <name>` header comment line, if present.
    public var author: String?

    public init(statements: [LDrawStatement]) {
        self.statements = statements

        var name: String?
        var category: String?
        var keywords: [String] = []
        var author: String?
        var bfcState = LDrawBFCState()
        var sawGeometry = false

        for statement in statements {
            switch statement {
            case .meta(let meta):
                switch meta {
                case .fileStart(let fileName):
                    if name == nil { name = fileName }
                case .category(let value):
                    if category == nil { category = value }
                case .keywords(let values):
                    keywords.append(contentsOf: values)
                case .bfc(let directives):
                    if !sawGeometry {
                        bfcState.apply(directives)
                    }
                case .comment(let text):
                    if author == nil, let parsedAuthor = Self.parseAuthor(from: text) {
                        author = parsedAuthor
                    }
                default:
                    break
                }
            case .subfileReference, .line, .triangle, .quadrilateral, .optionalLine:
                sawGeometry = true
            }
        }

        self.name = name
        self.category = category
        self.keywords = keywords
        self.author = author
        self.initialBFCState = bfcState
    }

    private static func parseAuthor(from text: String) -> String? {
        let substring = Substring(text)
        guard let colonIndex = substring.firstIndex(of: ":") else { return nil }
        let prefix = substring[substring.startIndex..<colonIndex].trimmingLDrawWhitespace()
        guard LDrawASCII.lowercasedKeyword(prefix) == "author" else { return nil }
        let rest = substring[substring.index(after: colonIndex)...].trimmingLDrawWhitespace()
        return String(rest)
    }
}
