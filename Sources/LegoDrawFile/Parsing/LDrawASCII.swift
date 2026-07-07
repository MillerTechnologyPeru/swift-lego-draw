/// Byte-level ASCII helpers used to keep keyword matching Foundation-free and to
/// avoid invoking Swift's Unicode case-folding/grapheme machinery, which is not
/// guaranteed to be available under Embedded Swift.
enum LDrawASCII {

    static func lowercased(_ byte: UInt8) -> UInt8 {
        (byte >= 0x41 && byte <= 0x5A) ? byte + 0x20 : byte
    }

    /// Lowercases an ASCII field into a new `String`. LDraw keywords are always ASCII,
    /// so this does not need to handle multi-byte UTF8 sequences specially.
    static func lowercasedKeyword(_ field: Substring) -> String {
        String(decoding: field.utf8.map(lowercased), as: UTF8.self)
    }
}

extension Substring {

    /// Trims leading/trailing spaces and tabs without relying on Foundation.
    func trimmingLDrawWhitespace() -> Substring {
        let view = utf8
        var start = startIndex
        var end = endIndex

        while start < end, view[start] == 0x20 || view[start] == 0x09 {
            start = view.index(after: start)
        }
        while end > start {
            let previous = view.index(before: end)
            guard view[previous] == 0x20 || view[previous] == 0x09 else { break }
            end = previous
        }
        return self[start..<end]
    }
}
