import Testing
@testable import LegoDrawFile

private struct MockResolver: LDrawPartResolver {
    var files: [String: String]

    func resolve(reference: String) throws(LDrawResolutionError) -> LDrawSourceFile? {
        let key = LDrawMultiPartDocument.normalizedName(reference)
        guard let text = files[key] else { return nil }
        do {
            return try LDrawParser.parseFile(text)
        } catch {
            throw LDrawResolutionError.parseErrorInResolvedPart(reference: reference, error: error)
        }
    }
}

@Suite struct ResolverTests {

    @Test func resolvesNestedSubfiles() throws {
        let resolver = MockResolver(files: [
            "sub.dat": "3 1 0 0 0 1 0 0 0 1 0"
        ])
        let file = try LDrawParser.parseFile(
            "1 16 0 0 0 1 0 0 0 1 0 0 0 1 sub.dat"
        )
        let modelResolver = LDrawModelResolver(resolver: resolver)
        let model = try modelResolver.resolve(file)

        #expect(model.children.count == 1)
        guard case .subfile(_, _, _, let child) = model.children[0] else {
            Issue.record("expected subfile node")
            return
        }
        #expect(child.children.count == 1)
    }

    @Test func missingPartOmitPolicyDropsNode() throws {
        let resolver = MockResolver(files: [:])
        let file = try LDrawParser.parseFile("1 16 0 0 0 1 0 0 0 1 0 0 0 1 missing.dat")
        let modelResolver = LDrawModelResolver(resolver: resolver, missingPartPolicy: .omit)
        let model = try modelResolver.resolve(file)
        #expect(model.children.isEmpty)
    }

    @Test func missingPartPlaceholderPolicyKeepsNode() throws {
        let resolver = MockResolver(files: [:])
        let file = try LDrawParser.parseFile("1 16 0 0 0 1 0 0 0 1 0 0 0 1 missing.dat")
        let modelResolver = LDrawModelResolver(resolver: resolver, missingPartPolicy: .placeholder)
        let model = try modelResolver.resolve(file)
        #expect(model.children.count == 1)
        guard case .missingSubfile(_, _, let fileName) = model.children[0] else {
            Issue.record("expected missingSubfile node")
            return
        }
        #expect(fileName == "missing.dat")
    }

    @Test func missingPartFailPolicyThrows() throws {
        let resolver = MockResolver(files: [:])
        let file = try LDrawParser.parseFile("1 16 0 0 0 1 0 0 0 1 0 0 0 1 missing.dat")
        let modelResolver = LDrawModelResolver(resolver: resolver, missingPartPolicy: .fail)
        #expect(throws: LDrawResolutionError.self) {
            try modelResolver.resolve(file)
        }
    }

    @Test func detectsCircularReferences() throws {
        let resolver = MockResolver(files: [
            "a.dat": "1 16 0 0 0 1 0 0 0 1 0 0 0 1 b.dat",
            "b.dat": "1 16 0 0 0 1 0 0 0 1 0 0 0 1 a.dat",
        ])
        let file = try LDrawParser.parseFile("1 16 0 0 0 1 0 0 0 1 0 0 0 1 a.dat")
        let modelResolver = LDrawModelResolver(resolver: resolver)
        #expect(throws: LDrawResolutionError.self) {
            try modelResolver.resolve(file)
        }
    }

    @Test func mpdEmbeddedFilesResolveWithoutExternalResolver() throws {
        let text = """
        0 FILE main.ldr
        1 16 0 0 0 1 0 0 0 1 0 0 0 1 sub.ldr
        0 NOFILE
        0 FILE sub.ldr
        3 1 0 0 0 1 0 0 0 1 0
        0 NOFILE
        """
        let document = try LDrawParser.parseMultiPartDocument(text)
        let resolver = MockResolver(files: [:])
        let modelResolver = LDrawModelResolver(resolver: resolver, missingPartPolicy: .fail)
        let model = try modelResolver.resolve(document)
        #expect(model.children.count == 1)
    }

    @Test func invertWindingReflectsNegativeDeterminant() throws {
        let resolver = MockResolver(files: [
            "sub.dat": "3 1 0 0 0 1 0 0 0 1 0"
        ])
        let file = try LDrawParser.parseFile(
            "1 16 0 0 0 -1 0 0 0 1 0 0 0 1 sub.dat"
        )
        let modelResolver = LDrawModelResolver(resolver: resolver)
        let model = try modelResolver.resolve(file)
        guard case .subfile(_, _, let invertWinding, _) = model.children[0] else {
            Issue.record("expected subfile node")
            return
        }
        #expect(invertWinding == true)
    }
}
