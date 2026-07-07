import Foundation
import LegoDrawFile
import LDrawSDL

/// Opens an interactive SDL3 window rendering a single LDraw file — a multi-part
/// model (`.ldr`/`.mpd`) or a single part (`.dat`) — via a software-projected,
/// painter's-algorithm triangle rasterizer (see `LDrawSDLViewer`). Drag with the
/// left mouse button to orbit; Escape or closing the window quits.
///
/// Usage: SDLLDrawViewer <input.ldr|input.dat> [--library <path>] [--color <code>]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    fail("""
    Usage: SDLLDrawViewer <input.ldr|input.dat> [--library <path>] [--color <code>]

    --library  Root of an LDraw parts library (containing parts/, p/, LDConfig.ldr).
               Defaults to $LDRAWDIR, then the current directory.
    --color    LDraw color code to render "current color" (16) geometry in — relevant
               for standalone parts, which are authored in color 16 by convention.
               Defaults to 7 (Light_Gray).
    """)
}

let inputURL = URL(fileURLWithPath: arguments[1])
var libraryPath = ProcessInfo.processInfo.environment["LDRAWDIR"] ?? FileManager.default.currentDirectoryPath
var colorCodeOverride: Int16?

var index = 2
while index < arguments.count {
    switch arguments[index] {
    case "--library":
        index += 1
        guard index < arguments.count else { fail("--library requires a path") }
        libraryPath = arguments[index]
    case "--color":
        index += 1
        guard index < arguments.count, let code = Int16(arguments[index]) else {
            fail("--color requires an LDraw color code, e.g. --color 4")
        }
        colorCodeOverride = code
    default:
        fail("Unknown argument: \(arguments[index])")
    }
    index += 1
}

let libraryURL = URL(fileURLWithPath: libraryPath, isDirectory: true)

do {
    let sourceText = try String(contentsOf: inputURL, encoding: .utf8)

    let resolver = FileSystemPartResolver(searchDirectories: [
        inputURL.deletingLastPathComponent(),
        libraryURL.appendingPathComponent("parts"),
        libraryURL.appendingPathComponent("parts/s"),
        libraryURL.appendingPathComponent("p"),
        libraryURL.appendingPathComponent("p/48"),
        libraryURL.appendingPathComponent("models"),
    ])
    let modelResolver = LDrawModelResolver(resolver: resolver, missingPartPolicy: .omit)

    let resolvedModel: ResolvedLDrawModel
    switch try LDrawParser.parseAuto(sourceText) {
    case .singleFile(let file):
        resolvedModel = try modelResolver.resolve(file)
    case .multiPartDocument(let document):
        resolvedModel = try modelResolver.resolve(document)
    }

    var colorTable = LDrawColorTable()
    let ldConfigURL = libraryURL.appendingPathComponent("LDConfig.ldr")
    if let ldConfigText = try? String(contentsOf: ldConfigURL, encoding: .utf8) {
        colorTable = (try? LDrawColorTable.parsing(ldConfigText: ldConfigText)) ?? colorTable
    }
    let defaultColorCode = colorCodeOverride ?? 7
    let defaultColor = colorTable.color(forCode: defaultColorCode) ?? LDrawResolvedColor(
        name: "Light_Gray", code: 7,
        red: 156, green: 163, blue: 168,
        edgeRed: 51, edgeGreen: 51, edgeBlue: 51
    )

    let flattener = LDrawSceneFlattener(colorTable: colorTable, defaultColor: defaultColor)
    let triangles = flattener.flatten(resolvedModel)
    guard !triangles.isEmpty else {
        fail("No renderable geometry found in \(inputURL.lastPathComponent) (missing parts library? pass --library)")
    }

    let viewer = LDrawSDLViewer(
        triangles: triangles,
        options: .init(windowTitle: inputURL.lastPathComponent)
    )
    try viewer.run()
} catch {
    fail("\(error)")
}
