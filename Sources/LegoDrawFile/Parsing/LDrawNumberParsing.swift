extension StringProtocol {

    public func parsedLDrawFloat(lineNumber: Int) throws(LDrawParseError) -> Float {
        guard let value = Float(self) else {
            throw LDrawParseError.invalidNumber(lineNumber: lineNumber, field: String(self))
        }
        return value
    }

    public func parsedLDrawInt(lineNumber: Int) throws(LDrawParseError) -> Int {
        guard let value = Int(self) else {
            throw LDrawParseError.invalidNumber(lineNumber: lineNumber, field: String(self))
        }
        return value
    }

    /// Parses a color field, recognizing palette indices, the special current-color (16)
    /// and edge-color (24) codes, and the `0x2RRGGBB` direct-color literal syntax.
    public func parsedLDrawColorReference(lineNumber: Int) throws(LDrawParseError) -> LDrawColorReference {
        if isLDrawDirectColorLiteral {
            let hexDigits = dropFirst(3)
            guard hexDigits.count == 6, let value = UInt32(hexDigits, radix: 16) else {
                throw LDrawParseError.invalidColorReference(lineNumber: lineNumber, field: String(self))
            }
            return .direct(
                red: UInt8((value >> 16) & 0xFF),
                green: UInt8((value >> 8) & 0xFF),
                blue: UInt8(value & 0xFF)
            )
        }

        guard let code = Int16(self) else {
            throw LDrawParseError.invalidColorReference(lineNumber: lineNumber, field: String(self))
        }

        switch code {
        case LDrawColorReference.currentColorCode:
            return .currentColor
        case LDrawColorReference.edgeColorCode:
            return .edgeColor
        default:
            return .index(code)
        }
    }

    /// Whether this field begins with the `0x2` direct-color prefix (case-insensitive `x`).
    fileprivate var isLDrawDirectColorLiteral: Bool {
        var iterator = utf8.makeIterator()
        guard iterator.next() == UInt8(ascii: "0") else { return false }
        guard let xByte = iterator.next(), xByte == UInt8(ascii: "x") || xByte == UInt8(ascii: "X") else {
            return false
        }
        guard iterator.next() == UInt8(ascii: "2") else { return false }
        return true
    }
}
