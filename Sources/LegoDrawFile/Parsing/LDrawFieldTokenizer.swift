/// Splits a single LDraw line into whitespace-delimited fields without importing Foundation.
public struct LDrawFieldTokenizer: Sendable {

    private let line: Substring
    private var currentIndex: Substring.Index

    public init(line: Substring) {
        self.line = line
        self.currentIndex = line.startIndex
    }

    /// Returns the next whitespace-delimited field, or `nil` once no fields remain.
    public mutating func nextField() -> Substring? {
        let utf8 = line.utf8
        while currentIndex < line.endIndex, Self.isWhitespace(utf8[currentIndex]) {
            currentIndex = utf8.index(after: currentIndex)
        }
        guard currentIndex < line.endIndex else { return nil }

        let start = currentIndex
        while currentIndex < line.endIndex, !Self.isWhitespace(utf8[currentIndex]) {
            currentIndex = utf8.index(after: currentIndex)
        }
        return line[start..<currentIndex]
    }

    /// Everything from the current position to the end of the line, with leading and
    /// trailing whitespace trimmed. Used for fields with rest-of-line semantics, such
    /// as subfile filenames and meta-command text, which may themselves contain spaces.
    public func restOfLine() -> Substring {
        let utf8 = line.utf8

        var start = currentIndex
        while start < line.endIndex, Self.isWhitespace(utf8[start]) {
            start = utf8.index(after: start)
        }
        guard start < line.endIndex else { return line[line.endIndex...] }

        var end = line.endIndex
        while end > start {
            let previous = utf8.index(before: end)
            guard Self.isWhitespace(utf8[previous]) else { break }
            end = previous
        }

        return line[start..<end]
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09
    }
}
