import AppKit
import Foundation
import SceneKit
import LegoDrawFile
import LDrawSceneKit

/// Renders a single LDraw file — a multi-part model (`.ldr`/`.mpd`) or a single part
/// (`.dat`) — to a PNG image via SceneKit. Both file kinds go through the exact same
/// pipeline: `LDrawParser.parseAuto` already distinguishes MPD from single-file input.
///
/// Usage: RenderLDrawModel <input.ldr|input.dat> [--library <path>] [--output <path.png>] [--color <code>]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    fail("""
    Usage: RenderLDrawModel <input.ldr|input.dat> [--library <path>] [--output <path.png>] [--color <code>]

    --library  Root of an LDraw parts library (containing parts/, p/, LDConfig.ldr).
               Defaults to $LDRAWDIR, then the current directory.
    --output   Where to write the rendered PNG. Defaults to the input name with a .png extension.
    --color    LDraw color code to render "current color" (16) geometry in — relevant
               for standalone parts, which are authored in color 16 by convention.
               Defaults to 7 (Light_Gray).
    """)
}

let inputURL = URL(fileURLWithPath: arguments[1])
var libraryPath = ProcessInfo.processInfo.environment["LDRAWDIR"] ?? FileManager.default.currentDirectoryPath
var outputPath: String?
var colorCodeOverride: Int16?

var index = 2
while index < arguments.count {
    switch arguments[index] {
    case "--library":
        index += 1
        guard index < arguments.count else { fail("--library requires a path") }
        libraryPath = arguments[index]
    case "--output":
        index += 1
        guard index < arguments.count else { fail("--output requires a path") }
        outputPath = arguments[index]
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
let outputURL = outputPath.map { URL(fileURLWithPath: $0) }
    ?? inputURL.deletingPathExtension().appendingPathExtension("png")

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

    let builder = LDrawSceneBuilder(options: .init(colorTable: colorTable, defaultColor: defaultColor))
    let modelNode = builder.buildNode(from: resolvedModel)

    let image = try render(modelNode)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fail("Failed to encode the rendered image as PNG")
    }
    try pngData.write(to: outputURL)
    print("Rendered \(inputURL.lastPathComponent) to \(outputURL.path)")
} catch {
    fail("\(error)")
}

func render(_ modelNode: SCNNode) throws -> NSImage {
    let scene = SCNScene()
    scene.rootNode.addChildNode(modelNode)

    let (minBound, maxBound) = modelNode.boundingBox
    let center = SCNVector3(
        (minBound.x + maxBound.x) / 2, (minBound.y + maxBound.y) / 2, (minBound.z + maxBound.z) / 2
    )
    let extent = max(maxBound.x - minBound.x, max(maxBound.y - minBound.y, maxBound.z - minBound.z))
    let distance = max(extent * 2.5, 10)

    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.camera?.zFar = 1_000_000
    cameraNode.position = SCNVector3(
        center.x + distance * 0.6, center.y - distance * 0.6, center.z + distance * 0.6
    )
    cameraNode.look(at: center)
    scene.rootNode.addChildNode(cameraNode)

    let keyLight = SCNNode()
    keyLight.light = SCNLight()
    keyLight.light?.type = .omni
    keyLight.light?.intensity = 1000
    keyLight.position = cameraNode.position
    scene.rootNode.addChildNode(keyLight)

    let ambientLight = SCNNode()
    ambientLight.light = SCNLight()
    ambientLight.light?.type = .ambient
    ambientLight.light?.intensity = 300
    scene.rootNode.addChildNode(ambientLight)

    let renderer = SCNRenderer(device: nil, options: nil)
    renderer.scene = scene
    renderer.pointOfView = cameraNode

    return renderer.snapshot(atTime: 0, with: CGSize(width: 1024, height: 1024), antialiasingMode: .multisampling4X)
}
