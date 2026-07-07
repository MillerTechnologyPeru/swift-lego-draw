/// Parses LDraw source text into statements and files.
public enum LDrawParser {

    /// Parses `text` as a single logical LDraw file (a `.dat`/`.ldr` part or model).
    ///
    /// - Throws: ``LDrawParseError`` if any line is malformed.
    public static func parseFile(_ text: some StringProtocol) throws(LDrawParseError) -> LDrawSourceFile {
        var scanner = LDrawLineScanner(text: text)
        var statements: [LDrawStatement] = []
        var lineNumber = 0
        while let line = scanner.nextLine() {
            lineNumber += 1
            if let statement = try parseStatement(line, lineNumber: lineNumber) {
                statements.append(statement)
            }
        }
        return LDrawSourceFile(statements: statements)
    }

    /// Parses `text` as an MPD (multi-part document): a main model plus zero or more
    /// `0 FILE`/`0 NOFILE`-delimited embedded submodel sections.
    ///
    /// If `text` contains no `0 FILE` statements at all, it is treated as a single-file
    /// document and returned as an ``LDrawMultiPartDocument`` with an empty
    /// `embeddedFiles` dictionary, so callers do not need to guess the format up front.
    public static func parseMultiPartDocument(
        _ text: some StringProtocol
    ) throws(LDrawParseError) -> LDrawMultiPartDocument {
        var scanner = LDrawLineScanner(text: text)
        var lineNumber = 0

        var sections: [(name: String, statements: [LDrawStatement])] = []
        var currentName: String?
        var currentStatements: [LDrawStatement] = []
        var preambleStatements: [LDrawStatement] = []

        func finalizeCurrentSection() {
            guard let name = currentName else { return }
            sections.append((name: name, statements: currentStatements))
            currentStatements = []
        }

        while let line = scanner.nextLine() {
            lineNumber += 1
            guard let statement = try parseStatement(line, lineNumber: lineNumber) else { continue }

            if case .meta(.fileStart(let name)) = statement {
                finalizeCurrentSection()
                currentName = name
                currentStatements = [statement]
                continue
            }

            if case .meta(.fileEnd) = statement {
                currentStatements.append(statement)
                finalizeCurrentSection()
                currentName = nil
                continue
            }

            if currentName == nil {
                preambleStatements.append(statement)
            } else {
                currentStatements.append(statement)
            }
        }
        finalizeCurrentSection()

        var embeddedFiles: [String: LDrawSourceFile] = [:]
        for section in sections {
            embeddedFiles[LDrawMultiPartDocument.normalizedName(section.name)] =
                LDrawSourceFile(statements: section.statements)
        }

        let mainFile: LDrawSourceFile
        if let firstSection = sections.first {
            mainFile = LDrawSourceFile(statements: firstSection.statements)
        } else {
            mainFile = LDrawSourceFile(statements: preambleStatements)
        }

        return LDrawMultiPartDocument(mainFile: mainFile, embeddedFiles: embeddedFiles)
    }

    /// Parses a single line into a statement. Returns `nil` for blank lines.
    static func parseStatement(_ line: Substring, lineNumber: Int) throws(LDrawParseError) -> LDrawStatement? {
        let trimmed = line.trimmingLDrawWhitespace()
        guard !trimmed.isEmpty else { return nil }

        var tokenizer = LDrawFieldTokenizer(line: trimmed)
        guard let typeField = tokenizer.nextField() else { return nil }
        guard typeField.utf8.count == 1, let typeByte = typeField.utf8.first else {
            throw LDrawParseError.unknownLineType(lineNumber: lineNumber, type: String(typeField))
        }

        switch typeByte {
        case UInt8(ascii: "0"):
            let content = tokenizer.restOfLine()
            return .meta(try LDrawMetaCommandParser.parse(content: content, lineNumber: lineNumber))
        case UInt8(ascii: "1"):
            return .subfileReference(try parseSubfileReference(&tokenizer, lineNumber: lineNumber))
        case UInt8(ascii: "2"):
            return .line(try parseLine(&tokenizer, lineNumber: lineNumber))
        case UInt8(ascii: "3"):
            return .triangle(try parseTriangle(&tokenizer, lineNumber: lineNumber))
        case UInt8(ascii: "4"):
            return .quadrilateral(try parseQuadrilateral(&tokenizer, lineNumber: lineNumber))
        case UInt8(ascii: "5"):
            return .optionalLine(try parseOptionalLine(&tokenizer, lineNumber: lineNumber))
        default:
            throw LDrawParseError.unknownLineType(lineNumber: lineNumber, type: String(typeField))
        }
    }

    private static func readColor(
        _ tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> LDrawColorReference {
        guard let field = tokenizer.nextField() else {
            throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 1, found: 0)
        }
        return try field.parsedLDrawColorReference(lineNumber: lineNumber)
    }

    private static func readFloats(
        _ count: Int, from tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> [Float] {
        var values: [Float] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            guard let field = tokenizer.nextField() else {
                throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: count, found: values.count)
            }
            values.append(try field.parsedLDrawFloat(lineNumber: lineNumber))
        }
        return values
    }

    private static func parseSubfileReference(
        _ tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> LDrawSubfileReference {
        let color = try readColor(&tokenizer, lineNumber: lineNumber)
        let values = try readFloats(12, from: &tokenizer, lineNumber: lineNumber)
        let fileName = tokenizer.restOfLine()
        guard !fileName.isEmpty else {
            throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 14, found: 13)
        }
        let transform = Matrix4(
            a: values[3], b: values[4], c: values[5], x: values[0],
            d: values[6], e: values[7], f: values[8], y: values[1],
            g: values[9], h: values[10], i: values[11], z: values[2]
        )
        return LDrawSubfileReference(color: color, transform: transform, fileName: String(fileName))
    }

    private static func parseLine(
        _ tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> LDrawLine {
        let color = try readColor(&tokenizer, lineNumber: lineNumber)
        let values = try readFloats(6, from: &tokenizer, lineNumber: lineNumber)
        return LDrawLine(
            color: color,
            start: Vector3(x: values[0], y: values[1], z: values[2]),
            end: Vector3(x: values[3], y: values[4], z: values[5])
        )
    }

    private static func parseTriangle(
        _ tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> LDrawTriangle {
        let color = try readColor(&tokenizer, lineNumber: lineNumber)
        let values = try readFloats(9, from: &tokenizer, lineNumber: lineNumber)
        return LDrawTriangle(
            color: color,
            vertex1: Vector3(x: values[0], y: values[1], z: values[2]),
            vertex2: Vector3(x: values[3], y: values[4], z: values[5]),
            vertex3: Vector3(x: values[6], y: values[7], z: values[8])
        )
    }

    private static func parseQuadrilateral(
        _ tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> LDrawQuadrilateral {
        let color = try readColor(&tokenizer, lineNumber: lineNumber)
        let values = try readFloats(12, from: &tokenizer, lineNumber: lineNumber)
        return LDrawQuadrilateral(
            color: color,
            vertex1: Vector3(x: values[0], y: values[1], z: values[2]),
            vertex2: Vector3(x: values[3], y: values[4], z: values[5]),
            vertex3: Vector3(x: values[6], y: values[7], z: values[8]),
            vertex4: Vector3(x: values[9], y: values[10], z: values[11])
        )
    }

    /// Parses `text`, automatically choosing single-file or MPD parsing based on
    /// whether the first statement is `0 FILE`.
    public static func parseAuto(_ text: some StringProtocol) throws(LDrawParseError) -> LDrawParseResult {
        if try isMultiPartDocument(text) {
            return .multiPartDocument(try parseMultiPartDocument(text))
        }
        return .singleFile(try parseFile(text))
    }

    private static func isMultiPartDocument(_ text: some StringProtocol) throws(LDrawParseError) -> Bool {
        var scanner = LDrawLineScanner(text: text)
        var lineNumber = 0
        while let line = scanner.nextLine() {
            lineNumber += 1
            guard let statement = try parseStatement(line, lineNumber: lineNumber) else { continue }
            if case .meta(.fileStart) = statement { return true }
            return false
        }
        return false
    }

    private static func parseOptionalLine(
        _ tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> LDrawOptionalLine {
        let color = try readColor(&tokenizer, lineNumber: lineNumber)
        let values = try readFloats(12, from: &tokenizer, lineNumber: lineNumber)
        return LDrawOptionalLine(
            color: color,
            start: Vector3(x: values[0], y: values[1], z: values[2]),
            end: Vector3(x: values[3], y: values[4], z: values[5]),
            control1: Vector3(x: values[6], y: values[7], z: values[8]),
            control2: Vector3(x: values[9], y: values[10], z: values[11])
        )
    }
}
