import Foundation
import LegoDrawFile

// MARK: - Model loading

/// Loads the 2×4 brick (3001.dat) from the LDraw library if available on the
/// file system (works when running as "Designed for iPad" on Mac), otherwise
/// falls back to a simple embedded box so the playground is always renderable.
func loadModel(colorCode: Int16 = 4) -> (ResolvedLDrawModel, LDrawResolvedColor, LDrawColorTable) {
    let ldrawDir = ProcessInfo.processInfo.environment["LDRAWDIR"]
        ?? "/Applications/Bricksmith/ldraw"
    let partsURL = URL(fileURLWithPath: ldrawDir)

    let colorTable: LDrawColorTable
    let ldConfigURL = partsURL.appendingPathComponent("LDConfig.ldr")
    if let text = try? String(contentsOf: ldConfigURL, encoding: .utf8),
       let table = try? LDrawColorTable.parsing(ldConfigText: text) {
        colorTable = table
    } else {
        colorTable = LDrawColorTable()
    }

    let defaultColor = colorTable.color(forCode: colorCode)
        ?? LDrawResolvedColor(name: "Red", code: 4,
                              red: 199, green: 20, blue: 20,
                              edgeRed: 0, edgeGreen: 0, edgeBlue: 0)

    // Try loading 3001.dat from the library
    let searchDirs = [
        partsURL.appendingPathComponent("parts"),
        partsURL.appendingPathComponent("parts/s"),
        partsURL.appendingPathComponent("p"),
        partsURL.appendingPathComponent("p/48"),
        partsURL.appendingPathComponent("models"),
    ]
    let resolver = FileSystemPartResolver(searchDirectories: searchDirs)
    let modelResolver = LDrawModelResolver(resolver: resolver, missingPartPolicy: .omit)

    let brickURL = partsURL.appendingPathComponent("parts/3001.dat")
    if let text = try? String(contentsOf: brickURL, encoding: .utf8),
       let file = try? LDrawParser.parseFile(text),
       let model = try? modelResolver.resolve(file) {
        return (model, defaultColor, colorTable)
    }

    // Fallback: simple embedded box
    let fallbackModel = makeFallbackModel()
    return (fallbackModel, defaultColor, colorTable)
}

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

// MARK: - File system resolver

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
