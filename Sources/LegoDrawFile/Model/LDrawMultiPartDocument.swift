/// A parsed MPD (multi-part document): a main model plus zero or more named submodel
/// sections embedded in the same file via `0 FILE` / `0 NOFILE`.
public struct LDrawMultiPartDocument: Sendable {
    public var mainFile: LDrawSourceFile
    /// Embedded sections keyed by lowercased name (LDraw file name matching is
    /// treated as case-insensitive); the section's own `name` retains original case.
    public var embeddedFiles: [String: LDrawSourceFile]

    public init(mainFile: LDrawSourceFile, embeddedFiles: [String: LDrawSourceFile]) {
        self.mainFile = mainFile
        self.embeddedFiles = embeddedFiles
    }

    /// Looks up an embedded section by name, case-insensitively.
    public func file(named name: String) -> LDrawSourceFile? {
        embeddedFiles[Self.normalizedName(name)]
    }

    static func normalizedName(_ name: String) -> String {
        LDrawASCII.lowercasedKeyword(Substring(name))
    }
}
