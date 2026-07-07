/// A resolved color from an LDraw `0 !COLOUR` definition (a palette entry, e.g. from
/// LDConfig.ldr or a model's own local color definitions).
public struct LDrawResolvedColor: Sendable, Equatable, Hashable {
    public var name: String
    public var code: Int16
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8
    public var edgeRed: UInt8
    public var edgeGreen: UInt8
    public var edgeBlue: UInt8
    public var edgeAlpha: UInt8
    public var finish: LDrawColorFinish

    public init(
        name: String,
        code: Int16,
        red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255,
        edgeRed: UInt8, edgeGreen: UInt8, edgeBlue: UInt8, edgeAlpha: UInt8 = 255,
        finish: LDrawColorFinish = .solid
    ) {
        self.name = name
        self.code = code
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.edgeRed = edgeRed
        self.edgeGreen = edgeGreen
        self.edgeBlue = edgeBlue
        self.edgeAlpha = edgeAlpha
        self.finish = finish
    }
}

/// A palette of `LDrawResolvedColor` values keyed by color code, as declared by
/// `0 !COLOUR` meta-commands (typically loaded from an LDConfig.ldr-style source
/// via ``LDrawColorTable/parsing(ldConfigText:)``).
public struct LDrawColorTable: Sendable {

    private var colorsByCode: [Int16: LDrawResolvedColor]

    public init() {
        self.colorsByCode = [:]
    }

    public mutating func insert(_ color: LDrawResolvedColor) {
        colorsByCode[color.code] = color
    }

    public func color(forCode code: Int16) -> LDrawResolvedColor? {
        colorsByCode[code]
    }

    public var allColors: [LDrawResolvedColor] {
        Array(colorsByCode.values)
    }

    /// Parses an LDConfig.ldr-style text blob — a stream of `0 !COLOUR` meta-commands —
    /// into a color table. Standard LDraw colors are not bundled with this library;
    /// callers supply the LDConfig.ldr contents themselves (e.g. loaded from a local
    /// parts library).
    public static func parsing(ldConfigText text: some StringProtocol) throws(LDrawParseError) -> LDrawColorTable {
        let file = try LDrawParser.parseFile(text)
        var table = LDrawColorTable()
        for statement in file.statements {
            if case .meta(.colourDefinition(let color)) = statement {
                table.insert(color)
            }
        }
        return table
    }
}
