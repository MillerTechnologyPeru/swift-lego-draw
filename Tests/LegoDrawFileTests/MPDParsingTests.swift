import Testing
@testable import LegoDrawFile

@Suite struct MPDParsingTests {

    static let sampleMPD = """
    0 FILE main.ldr
    0 Main Model
    0 Author: Someone
    1 16 0 0 0 1 0 0 0 1 0 0 0 1 sub.ldr
    1 4 0 0 0 1 0 0 0 1 0 0 0 1 3001.dat
    0 NOFILE
    0 FILE sub.ldr
    0 Sub Model
    3 1 0 0 0 1 0 0 0 1 0
    0 NOFILE
    """

    @Test func parsesMultipleSections() throws {
        let document = try LDrawParser.parseMultiPartDocument(Self.sampleMPD)
        #expect(document.mainFile.name == "main.ldr")
        #expect(document.mainFile.author == "Someone")
        #expect(document.embeddedFiles.count == 2)
        #expect(document.file(named: "sub.ldr") != nil)
    }

    @Test func lookupIsCaseInsensitive() throws {
        let document = try LDrawParser.parseMultiPartDocument(Self.sampleMPD)
        #expect(document.file(named: "SUB.LDR") != nil)
        #expect(document.file(named: "Sub.Ldr") != nil)
    }

    @Test func mainFileIsFirstSection() throws {
        let document = try LDrawParser.parseMultiPartDocument(Self.sampleMPD)
        guard case .subfileReference(let ref) = document.mainFile.statements.first(where: {
            if case .subfileReference = $0 { return true }
            return false
        }) else {
            Issue.record("expected a subfile reference in main file")
            return
        }
        #expect(ref.fileName == "sub.ldr")
    }

    @Test func handlesImplicitEndOfSectionAtEOF() throws {
        let text = """
        0 FILE only.ldr
        3 1 0 0 0 1 0 0 0 1 0
        """
        let document = try LDrawParser.parseMultiPartDocument(text)
        #expect(document.mainFile.name == "only.ldr")
        #expect(document.mainFile.statements.contains {
            if case .triangle = $0 { return true }
            return false
        })
    }

    @Test func singleFileInputSynthesizesOneEntryDocument() throws {
        let text = """
        0 Just A Part
        3 1 0 0 0 1 0 0 0 1 0
        """
        let document = try LDrawParser.parseMultiPartDocument(text)
        #expect(document.embeddedFiles.isEmpty)
        #expect(document.mainFile.statements.count == 2)
    }

    @Test func parseAutoDetectsMPD() throws {
        let result = try LDrawParser.parseAuto(Self.sampleMPD)
        guard case .multiPartDocument = result else {
            Issue.record("expected multiPartDocument")
            return
        }
    }

    @Test func parseAutoDetectsSingleFile() throws {
        let result = try LDrawParser.parseAuto("3 1 0 0 0 1 0 0 0 1 0")
        guard case .singleFile = result else {
            Issue.record("expected singleFile")
            return
        }
    }
}
