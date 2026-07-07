/// A color as written in an LDraw statement's color field.
public enum LDrawColorReference: Sendable, Equatable, Hashable {

    /// A palette index (see `LDrawColorTable`).
    case index(Int16)

    /// A direct color in the `0x2RRGGBB` syntax, bypassing the palette.
    case direct(red: UInt8, green: UInt8, blue: UInt8)

    /// Color code 16: inherit the color of the enclosing subfile reference.
    case currentColor

    /// Color code 24: inherit the edge/complement color of the enclosing subfile reference.
    case edgeColor
}

extension LDrawColorReference {

    /// Color code 16, per the LDraw specification.
    public static let currentColorCode: Int16 = 16

    /// Color code 24, per the LDraw specification.
    public static let edgeColorCode: Int16 = 24
}
