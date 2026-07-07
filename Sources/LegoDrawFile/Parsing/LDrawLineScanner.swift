/// Splits LDraw source text into lines without importing Foundation, handling
/// LF, CRLF, and lone-CR line endings. Operates on `Substring` byte indices so
/// each returned line is a zero-copy slice of the original text.
public struct LDrawLineScanner: Sendable {

    private let text: Substring
    private var currentIndex: Substring.Index

    public init(text: some StringProtocol) {
        self.text = Substring(text)
        self.currentIndex = self.text.startIndex
    }

    /// Returns the next line (excluding its terminator), or `nil` once the input is exhausted.
    public mutating func nextLine() -> Substring? {
        guard currentIndex < text.endIndex else { return nil }

        let utf8 = text.utf8
        var index = currentIndex
        while index < text.endIndex {
            let byte = utf8[index]
            if byte == 0x0A || byte == 0x0D {
                let line = text[currentIndex..<index]
                var next = utf8.index(after: index)
                if byte == 0x0D, next < text.endIndex, utf8[next] == 0x0A {
                    next = utf8.index(after: next)
                }
                currentIndex = next
                return line
            }
            index = utf8.index(after: index)
        }

        let line = text[currentIndex..<text.endIndex]
        currentIndex = text.endIndex
        return line
    }
}
