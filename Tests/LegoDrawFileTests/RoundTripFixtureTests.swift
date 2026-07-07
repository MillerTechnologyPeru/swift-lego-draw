import Foundation
import Testing
@testable import LegoDrawFile

@Suite struct RoundTripFixtureTests {

    private func loadFixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
        let resolvedURL = try #require(url, "missing fixture \(name)")
        return try String(contentsOf: resolvedURL, encoding: .utf8)
    }

    @Test func parsesSimpleBrickReference() throws {
        let text = try loadFixture("simple_brick_reference.ldr")
        let file = try LDrawParser.parseFile(text)

        #expect(file.author == "Test Fixture")
        #expect(file.initialBFCState.isCertified == true)
        #expect(file.initialBFCState.windingIsCCW == true)

        let subfileReferences = file.statements.compactMap { statement -> LDrawSubfileReference? in
            if case .subfileReference(let ref) = statement { return ref }
            return nil
        }
        #expect(subfileReferences.count == 1)
        #expect(subfileReferences.first?.fileName == "3001.dat")
        #expect(subfileReferences.first?.color == .index(4))
    }

    @Test func parsesSmallMultipart() throws {
        let text = try loadFixture("small_multipart.mpd")
        let document = try LDrawParser.parseMultiPartDocument(text)

        #expect(document.mainFile.name == "main.ldr")
        #expect(document.mainFile.author == "Test Fixture")
        #expect(document.embeddedFiles.count == 2)

        let submodel = try #require(document.file(named: "submodel.ldr"))
        let triangles = submodel.statements.compactMap { statement -> LDrawTriangle? in
            if case .triangle(let tri) = statement { return tri }
            return nil
        }
        #expect(triangles.count == 1)

        let quads = submodel.statements.compactMap { statement -> LDrawQuadrilateral? in
            if case .quadrilateral(let quad) = statement { return quad }
            return nil
        }
        #expect(quads.count == 1)
    }

    @Test func resolvesSmallMultipartWithoutExternalParts() throws {
        struct EmptyResolver: LDrawPartResolver {
            func resolve(reference: String) throws(LDrawResolutionError) -> LDrawSourceFile? { nil }
        }

        let text = try loadFixture("small_multipart.mpd")
        let document = try LDrawParser.parseMultiPartDocument(text)
        let resolver = LDrawModelResolver(resolver: EmptyResolver(), missingPartPolicy: .placeholder)
        let model = try resolver.resolve(document)

        // main.ldr references submodel.ldr (embedded, resolves) and 3001.dat (external, missing -> placeholder)
        #expect(model.children.count == 2)
    }

    @Test func parsesMinimalLDConfig() throws {
        let text = try loadFixture("minimal_ldconfig.ldr")
        let table = try LDrawColorTable.parsing(ldConfigText: text)

        let black = try #require(table.color(forCode: 0))
        #expect(black.name == "Black")
        #expect(black.red == 0x05)

        let transClear = try #require(table.color(forCode: 47))
        #expect(transClear.alpha == 128)

        let chrome = try #require(table.color(forCode: 383))
        #expect(chrome.finish == .chrome)

        let rubber = try #require(table.color(forCode: 256))
        #expect(rubber.finish == .rubber)

        #expect(table.allColors.count == 5)
    }
}
