/// A parsed line-type-0 (comment/meta-command) statement.
///
/// The commands prioritized by the LDraw spec for scene assembly (BFC, `FILE`/`NOFILE`,
/// `STEP`, `!COLOUR`, `!CATEGORY`, `!KEYWORDS`, header fields, `!TEXMAP`) are modeled
/// as first-class cases. Anything else — vendor extensions, `SYNTH...`, `!SAVE`, etc. —
/// is preserved via ``unrecognized(keyword:rawLine:)`` so no information is lost.
public enum LDrawMetaCommand: Sendable, Equatable {
    case comment(String)
    case bfc([LDrawBFCDirective])
    case step
    /// `nil` represents `ROTSTEP END`.
    case rotStep(LDrawRotStep?)
    case fileStart(name: String)
    case fileEnd
    case colourDefinition(LDrawResolvedColor)
    case category(String)
    case keywords([String])
    case ldrawOrg(String)
    case license(String)
    case help(String)
    case history(String)
    case cmdline(String)
    case clear
    case pause
    case noStep
    case texmap(LDrawTexmapDirective)
    case unrecognized(keyword: String?, rawLine: String)
}

/// The payload of a `0 ROTSTEP x y z [REL|ABS|ADD]` statement.
public struct LDrawRotStep: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case relative
        case absolute
        case additive
    }

    public var rotation: Vector3
    public var mode: Mode

    public init(rotation: Vector3, mode: Mode) {
        self.rotation = rotation
        self.mode = mode
    }
}

/// The payload of a `0 !TEXMAP ...` statement. `!TEXMAP` blocks span multiple lines
/// (`START`/`NEXT` ... geometry ... `FALLBACK` ... geometry ... `END`); the parameter
/// text of `START`/`NEXT` is preserved verbatim rather than fully modeled.
public enum LDrawTexmapDirective: Sendable, Equatable {
    case start(raw: String)
    case next(raw: String)
    case fallback
    case end
}
