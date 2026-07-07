/// Parses the content following the leading `0` line-type token into a structured
/// ``LDrawMetaCommand``.
enum LDrawMetaCommandParser {

    /// - Parameter content: everything on the line after the `0` token, with leading
    ///   whitespace already stripped (a plain comment line has arbitrary text here).
    static func parse(content: Substring, lineNumber: Int) throws(LDrawParseError) -> LDrawMetaCommand {
        var tokenizer = LDrawFieldTokenizer(line: content)
        guard let keyword = tokenizer.nextField() else {
            return .comment("")
        }

        switch LDrawASCII.lowercasedKeyword(keyword) {
        case "bfc":
            return .bfc(try parseBFC(&tokenizer, lineNumber: lineNumber))
        case "step":
            return .step
        case "rotstep":
            return .rotStep(try parseRotStep(&tokenizer, lineNumber: lineNumber))
        case "file":
            return .fileStart(name: String(tokenizer.restOfLine()))
        case "nofile":
            return .fileEnd
        case "clear":
            return .clear
        case "pause":
            return .pause
        case "nostep":
            return .noStep
        case "!colour":
            return .colourDefinition(try parseColourDefinition(&tokenizer, lineNumber: lineNumber))
        case "!category":
            return .category(String(tokenizer.restOfLine()))
        case "!keywords":
            return .keywords(splitKeywords(tokenizer.restOfLine()))
        case "!ldraw_org":
            return .ldrawOrg(String(tokenizer.restOfLine()))
        case "!license":
            return .license(String(tokenizer.restOfLine()))
        case "!help":
            return .help(String(tokenizer.restOfLine()))
        case "!history":
            return .history(String(tokenizer.restOfLine()))
        case "!cmdline":
            return .cmdline(String(tokenizer.restOfLine()))
        case "!texmap":
            return .texmap(try parseTexmap(&tokenizer, content: content, lineNumber: lineNumber))
        default:
            if keyword.first == "!" {
                return .unrecognized(keyword: String(keyword), rawLine: String(content))
            }
            return .comment(String(content))
        }
    }

    private static func parseBFC(
        _ tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> [LDrawBFCDirective] {
        var directives: [LDrawBFCDirective] = []
        while let field = tokenizer.nextField() {
            switch LDrawASCII.lowercasedKeyword(field) {
            case "certify": directives.append(.certify)
            case "nocertify": directives.append(.noCertify)
            case "cw": directives.append(.cw)
            case "ccw": directives.append(.ccw)
            case "clip": directives.append(.clip)
            case "noclip": directives.append(.noClip)
            case "invertnext": directives.append(.invertNext)
            default:
                throw LDrawParseError.malformedLine(lineNumber: lineNumber, content: String(field))
            }
        }
        return directives.isEmpty ? [.certify] : directives
    }

    private static func parseRotStep(
        _ tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> LDrawRotStep? {
        guard let first = tokenizer.nextField() else { return nil }
        if LDrawASCII.lowercasedKeyword(first) == "end" {
            return nil
        }

        guard let yField = tokenizer.nextField(), let zField = tokenizer.nextField() else {
            throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 3, found: 1)
        }
        let rotation = Vector3(
            x: try first.parsedLDrawFloat(lineNumber: lineNumber),
            y: try yField.parsedLDrawFloat(lineNumber: lineNumber),
            z: try zField.parsedLDrawFloat(lineNumber: lineNumber)
        )

        var mode: LDrawRotStep.Mode = .relative
        if let modeField = tokenizer.nextField() {
            switch LDrawASCII.lowercasedKeyword(modeField) {
            case "rel": mode = .relative
            case "abs": mode = .absolute
            case "add": mode = .additive
            default: break
            }
        }
        return LDrawRotStep(rotation: rotation, mode: mode)
    }

    private static func parseColourDefinition(
        _ tokenizer: inout LDrawFieldTokenizer, lineNumber: Int
    ) throws(LDrawParseError) -> LDrawResolvedColor {
        guard let nameField = tokenizer.nextField() else {
            throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 1, found: 0)
        }

        var code: Int16?
        var red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0
        var edgeRed: UInt8 = 0, edgeGreen: UInt8 = 0, edgeBlue: UInt8 = 0
        var alpha: UInt8 = 255
        var edgeAlpha: UInt8 = 255
        var finish: LDrawColorFinish = .solid

        while let field = tokenizer.nextField() {
            switch LDrawASCII.lowercasedKeyword(field) {
            case "code":
                guard let value = tokenizer.nextField() else {
                    throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 1, found: 0)
                }
                code = Int16(try value.parsedLDrawInt(lineNumber: lineNumber))
            case "value":
                guard let value = tokenizer.nextField() else {
                    throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 1, found: 0)
                }
                (red, green, blue) = try parseHexColor(value, lineNumber: lineNumber)
            case "edge":
                guard let value = tokenizer.nextField() else {
                    throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 1, found: 0)
                }
                (edgeRed, edgeGreen, edgeBlue) = try parseHexColor(value, lineNumber: lineNumber)
            case "alpha":
                guard let value = tokenizer.nextField() else {
                    throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 1, found: 0)
                }
                alpha = UInt8(try value.parsedLDrawInt(lineNumber: lineNumber))
                edgeAlpha = alpha
            case "luminance":
                _ = tokenizer.nextField()
            case "chrome":
                finish = .chrome
            case "pearlescent":
                finish = .pearlescent
            case "rubber":
                finish = .rubber
            case "matte_metallic":
                finish = .matteMetallic
            case "metal":
                finish = .metal
            case "material":
                finish = .material(raw: String(tokenizer.restOfLine()))
            default:
                break
            }
        }

        guard let resolvedCode = code else {
            throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 1, found: 0)
        }

        return LDrawResolvedColor(
            name: String(nameField),
            code: resolvedCode,
            red: red, green: green, blue: blue, alpha: alpha,
            edgeRed: edgeRed, edgeGreen: edgeGreen, edgeBlue: edgeBlue, edgeAlpha: edgeAlpha,
            finish: finish
        )
    }

    private static func parseHexColor(
        _ field: Substring, lineNumber: Int
    ) throws(LDrawParseError) -> (UInt8, UInt8, UInt8) {
        var hex = field
        if hex.first == "#" {
            hex = hex.dropFirst()
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            throw LDrawParseError.invalidNumber(lineNumber: lineNumber, field: String(field))
        }
        return (UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
    }

    private static func splitKeywords(_ text: Substring) -> [String] {
        text.split(separator: ",").map { String($0.trimmingLDrawWhitespace()) }
    }

    private static func parseTexmap(
        _ tokenizer: inout LDrawFieldTokenizer, content: Substring, lineNumber: Int
    ) throws(LDrawParseError) -> LDrawTexmapDirective {
        guard let field = tokenizer.nextField() else {
            throw LDrawParseError.wrongFieldCount(lineNumber: lineNumber, expected: 1, found: 0)
        }
        switch LDrawASCII.lowercasedKeyword(field) {
        case "start": return .start(raw: String(tokenizer.restOfLine()))
        case "next": return .next(raw: String(tokenizer.restOfLine()))
        case "fallback": return .fallback
        case "end": return .end
        default:
            throw LDrawParseError.malformedLine(lineNumber: lineNumber, content: String(content))
        }
    }
}
