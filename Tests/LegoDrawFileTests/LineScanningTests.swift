import Testing
@testable import LegoDrawFile

@Suite struct LineScanningTests {

    @Test func splitsLFLines() {
        var scanner = LDrawLineScanner(text: "a\nb\nc")
        #expect(scanner.nextLine() == "a")
        #expect(scanner.nextLine() == "b")
        #expect(scanner.nextLine() == "c")
        #expect(scanner.nextLine() == nil)
    }

    @Test func splitsCRLFLines() {
        var scanner = LDrawLineScanner(text: "a\r\nb\r\nc")
        #expect(scanner.nextLine() == "a")
        #expect(scanner.nextLine() == "b")
        #expect(scanner.nextLine() == "c")
        #expect(scanner.nextLine() == nil)
    }

    @Test func splitsLoneCRLines() {
        var scanner = LDrawLineScanner(text: "a\rb\rc")
        #expect(scanner.nextLine() == "a")
        #expect(scanner.nextLine() == "b")
        #expect(scanner.nextLine() == "c")
        #expect(scanner.nextLine() == nil)
    }

    @Test func handlesEmptyLinesAndTrailingNewline() {
        var scanner = LDrawLineScanner(text: "a\n\nb\n")
        #expect(scanner.nextLine() == "a")
        #expect(scanner.nextLine() == "")
        #expect(scanner.nextLine() == "b")
        #expect(scanner.nextLine() == nil)
    }

    @Test func tokenizesFields() {
        var tokenizer = LDrawFieldTokenizer(line: "1 16  0 0 0 1 0 0 0 1 0 0 0 1 3001.dat")
        #expect(tokenizer.nextField() == "1")
        #expect(tokenizer.nextField() == "16")
        #expect(tokenizer.nextField() == "0")
    }

    @Test func restOfLineCapturesFilenameWithSpaces() {
        var tokenizer = LDrawFieldTokenizer(line: "1 16 0 0 0 1 0 0 0 1 0 0 0 1 Brick 2 x 4.dat")
        for _ in 0..<14 { _ = tokenizer.nextField() }
        #expect(tokenizer.restOfLine() == "Brick 2 x 4.dat")
    }

    @Test func parsesFloats() throws {
        #expect(try "1.5".parsedLDrawFloat(lineNumber: 1) == 1.5)
        #expect(try "-2".parsedLDrawFloat(lineNumber: 1) == -2)
        #expect(throws: LDrawParseError.self) {
            try "abc".parsedLDrawFloat(lineNumber: 1)
        }
    }

    @Test func parsesColorReferences() throws {
        #expect(try "16".parsedLDrawColorReference(lineNumber: 1) == .currentColor)
        #expect(try "24".parsedLDrawColorReference(lineNumber: 1) == .edgeColor)
        #expect(try "4".parsedLDrawColorReference(lineNumber: 1) == .index(4))
        #expect(
            try "0x2FF00FF".parsedLDrawColorReference(lineNumber: 1)
                == .direct(red: 0xFF, green: 0x00, blue: 0xFF)
        )
    }
}
