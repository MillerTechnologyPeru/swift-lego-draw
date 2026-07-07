import Testing
@testable import LegoDrawFile

@Suite struct StatementParsingTests {

    @Test func parsesSubfileReference() throws {
        let statement = try LDrawParser.parseStatement(
            "1 16 10 20 30 1 0 0 0 1 0 0 0 1 3001.dat", lineNumber: 1
        )
        #expect(
            statement == .subfileReference(
                LDrawSubfileReference(
                    color: .currentColor,
                    transform: Matrix4(
                        a: 1, b: 0, c: 0, x: 10,
                        d: 0, e: 1, f: 0, y: 20,
                        g: 0, h: 0, i: 1, z: 30
                    ),
                    fileName: "3001.dat"
                )
            )
        )
    }

    @Test func parsesSubfileReferenceWithSpacesInFileName() throws {
        let statement = try LDrawParser.parseStatement(
            "1 4 0 0 0 1 0 0 0 1 0 0 0 1 Brick 2 x 4.dat", lineNumber: 1
        )
        guard case .subfileReference(let ref) = statement else {
            Issue.record("expected subfileReference")
            return
        }
        #expect(ref.fileName == "Brick 2 x 4.dat")
    }

    @Test func parsesTriangle() throws {
        let statement = try LDrawParser.parseStatement(
            "3 1 0 0 0 1 0 0 0 1 0", lineNumber: 1
        )
        #expect(
            statement == .triangle(
                LDrawTriangle(
                    color: .index(1),
                    vertex1: .zero,
                    vertex2: Vector3(x: 1, y: 0, z: 0),
                    vertex3: Vector3(x: 0, y: 1, z: 0)
                )
            )
        )
    }

    @Test func parsesQuadrilateral() throws {
        let statement = try LDrawParser.parseStatement(
            "4 16 0 0 0 1 0 0 1 1 0 0 1 0", lineNumber: 1
        )
        guard case .quadrilateral = statement else {
            Issue.record("expected quadrilateral")
            return
        }
    }

    @Test func parsesOptionalLine() throws {
        let statement = try LDrawParser.parseStatement(
            "5 24 0 0 0 1 0 0 0 1 0 1 1 0", lineNumber: 1
        )
        #expect(statement != nil)
        guard case .optionalLine(let line) = statement else {
            Issue.record("expected optionalLine")
            return
        }
        #expect(line.color == .edgeColor)
    }

    @Test func throwsOnWrongFieldCount() {
        #expect(throws: LDrawParseError.self) {
            try LDrawParser.parseStatement("3 1 0 0 0", lineNumber: 5)
        }
    }

    @Test func throwsOnUnknownLineType() {
        #expect(throws: LDrawParseError.self) {
            try LDrawParser.parseStatement("9 foo", lineNumber: 5)
        }
    }

    @Test func returnsNilForBlankLine() throws {
        let statement = try LDrawParser.parseStatement("   ", lineNumber: 1)
        #expect(statement == nil)
    }

    @Test func parsesBFCCertifyCCW() throws {
        let statement = try LDrawParser.parseStatement("0 BFC CERTIFY CCW", lineNumber: 1)
        #expect(statement == .meta(.bfc([.certify, .ccw])))
    }

    @Test func parsesBFCInvertNext() throws {
        let statement = try LDrawParser.parseStatement("0 BFC INVERTNEXT", lineNumber: 1)
        #expect(statement == .meta(.bfc([.invertNext])))
    }

    @Test func bfcStateAppliesDirectivesInOrder() {
        var state = LDrawBFCState()
        state.apply([.certify, .cw])
        #expect(state.isCertified == true)
        #expect(state.windingIsCCW == false)
    }

    @Test func parsesFileStartAndEnd() throws {
        #expect(try LDrawParser.parseStatement("0 FILE main.ldr", lineNumber: 1) == .meta(.fileStart(name: "main.ldr")))
        #expect(try LDrawParser.parseStatement("0 NOFILE", lineNumber: 1) == .meta(.fileEnd))
    }

    @Test func parsesCategoryAndKeywords() throws {
        #expect(try LDrawParser.parseStatement("0 !CATEGORY Brick", lineNumber: 1) == .meta(.category("Brick")))
        #expect(
            try LDrawParser.parseStatement("0 !KEYWORDS lego, brick, 2x4", lineNumber: 1)
                == .meta(.keywords(["lego", "brick", "2x4"]))
        )
    }

    @Test func parsesColourDefinition() throws {
        let statement = try LDrawParser.parseStatement(
            "0 !COLOUR Red CODE 4 VALUE #FF0000 EDGE #330000 ALPHA 128", lineNumber: 1
        )
        guard case .meta(.colourDefinition(let color)) = statement else {
            Issue.record("expected colourDefinition")
            return
        }
        #expect(color.name == "Red")
        #expect(color.code == 4)
        #expect(color.red == 0xFF)
        #expect(color.green == 0x00)
        #expect(color.blue == 0x00)
        #expect(color.alpha == 128)
        #expect(color.edgeRed == 0x33)
    }

    @Test func parsesChromeFinish() throws {
        let statement = try LDrawParser.parseStatement(
            "0 !COLOUR Chrome_Silver CODE 383 VALUE #E8E3E3 EDGE #333333 CHROME", lineNumber: 1
        )
        guard case .meta(.colourDefinition(let color)) = statement else {
            Issue.record("expected colourDefinition")
            return
        }
        #expect(color.finish == .chrome)
    }

    @Test func plainCommentFallsBackToComment() throws {
        let statement = try LDrawParser.parseStatement("0 Name: 3001.dat", lineNumber: 1)
        #expect(statement == .meta(.comment("Name: 3001.dat")))
    }

    @Test func unrecognizedBangMetaPreservesRawLine() throws {
        let statement = try LDrawParser.parseStatement("0 !LPUB SOMETHING weird", lineNumber: 1)
        #expect(statement == .meta(.unrecognized(keyword: "!LPUB", rawLine: "!LPUB SOMETHING weird")))
    }

    @Test func parsesFileEndToEnd() throws {
        let text = """
        0 2 x 4 Brick
        0 Name: 3001.dat
        0 Author: Someone
        0 !CATEGORY Brick
        0 BFC CERTIFY CCW
        1 16 0 0 0 1 0 0 0 1 0 0 0 1 stud.dat
        4 16 1 0 0 1 0 1 1 1 1 0 1 0
        """
        let file = try LDrawParser.parseFile(text)
        #expect(file.author == "Someone")
        #expect(file.category == "Brick")
        #expect(file.initialBFCState.isCertified == true)
        #expect(file.initialBFCState.windingIsCCW == true)
        #expect(file.statements.count == 7)
    }
}
