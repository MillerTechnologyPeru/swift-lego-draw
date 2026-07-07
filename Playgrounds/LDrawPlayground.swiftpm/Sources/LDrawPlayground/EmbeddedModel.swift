import Foundation
import LegoDrawFile

// MARK: - Model loading

/// Loads the 2×4 brick (3001.dat).  Resolution order:
/// 1. Bundled `ldraw/` resource directory (always present in the app bundle)
/// 2. System LDraw library via LDRAWDIR env var or /Applications/Bricksmith/ldraw
/// 3. Hardcoded fallback box
func loadModel(colorCode: Int16 = 4) -> (ResolvedLDrawModel, LDrawResolvedColor, LDrawColorTable) {

    // Build search directories: bundled first, then system library
    var searchDirs: [URL] = []

    if let bundledLDraw = Bundle.main.url(forResource: "ldraw", withExtension: nil) {
        searchDirs += [
            bundledLDraw.appendingPathComponent("parts"),
            bundledLDraw.appendingPathComponent("parts/s"),
            bundledLDraw.appendingPathComponent("p"),
            bundledLDraw.appendingPathComponent("p/48"),
        ]
    }

    let systemBase = URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["LDRAWDIR"] ?? "/Applications/Bricksmith/ldraw")
    searchDirs += [
        systemBase.appendingPathComponent("parts"),
        systemBase.appendingPathComponent("parts/s"),
        systemBase.appendingPathComponent("p"),
        systemBase.appendingPathComponent("p/48"),
    ]

    // Color table from bundled or system LDConfig.ldr
    let colorTable: LDrawColorTable = {
        let candidates = [
            Bundle.main.url(forResource: "ldraw/LDConfig", withExtension: "ldr"),
            Optional(systemBase.appendingPathComponent("LDConfig.ldr")),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let table = try? LDrawColorTable.parsing(ldConfigText: text) {
                return table
            }
        }
        return LDrawColorTable()
    }()

    let defaultColor = colorTable.color(forCode: colorCode)
        ?? LDrawResolvedColor(name: "Red", code: 4,
                              red: 199, green: 20, blue: 20,
                              edgeRed: 0, edgeGreen: 0, edgeBlue: 0)

    let resolver = FileSystemPartResolver(searchDirectories: searchDirs)
    let modelResolver = LDrawModelResolver(resolver: resolver, missingPartPolicy: .omit)

    // Try loading 3001.dat
    for dir in searchDirs {
        let url = dir.appendingPathComponent("3001.dat")
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let file = try? LDrawParser.parseFile(text),
           let model = try? modelResolver.resolve(file) {
            return (model, defaultColor, colorTable)
        }
    }

    // Fallback: simple embedded box
    return (makeFallbackModel(), defaultColor, colorTable)
}

// MARK: - Fallback

private func makeFallbackModel() -> ResolvedLDrawModel {
    let src = """
    0 Brick
    0 BFC CERTIFY CCW
    4 4 -40 0 -20  40 0 -20  40 0 20  -40 0 20
    4 4 -40 24 -20  -40 24 20  40 24 20  40 24 -20
    4 4 -40 0 -20  -40 24 -20  40 24 -20  40 0 -20
    4 4  40 0 -20   40 24 -20  40 24 20   40 0 20
    4 4  40 0  20   40 24  20 -40 24 20  -40 0 20
    4 4 -40 0  20  -40 24  20 -40 24 -20 -40 0 -20
    """
    let file = try! LDrawParser.parseFile(src)
    return try! LDrawModelResolver(resolver: NoOpResolver(), missingPartPolicy: .omit).resolve(file)
}

// MARK: - Resolvers

struct FileSystemPartResolver: LDrawPartResolver {
    var searchDirectories: [URL]

    func resolve(reference: String) throws(LDrawResolutionError) -> LDrawSourceFile? {
        let normalized = reference.replacingOccurrences(of: "\\", with: "/")
        for dir in searchDirectories {
            for name in [normalized, normalized.lowercased()] {
                let url = dir.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                guard let file = try? LDrawParser.parseFile(text) else { continue }
                return file
            }
        }
        return nil
    }
}

private struct NoOpResolver: LDrawPartResolver {
    func resolve(reference: String) throws(LDrawResolutionError) -> LDrawSourceFile? { nil }
}
