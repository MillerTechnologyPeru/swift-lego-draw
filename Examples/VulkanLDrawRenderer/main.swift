#if os(Linux)
import Foundation
import LegoDrawFile
import LDrawVulkan

// MARK: - CLI args

var ldrawLibPath: String = ProcessInfo.processInfo.environment["LDRAWDIR"] ?? ""
var ldConfigPath: String = ""
var colorCode: Int = 4   // red
var outputPath: String = "output.ppm"
var width = 800
var height = 600
var inputPath: String = ""

var args = CommandLine.arguments.dropFirst()
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--library": ldrawLibPath = args.removeFirst()
    case "--ldconfig": ldConfigPath = args.removeFirst()
    case "--color": colorCode = Int(args.removeFirst()) ?? colorCode
    case "--output": outputPath = args.removeFirst()
    case "--width": width = Int(args.removeFirst()) ?? width
    case "--height": height = Int(args.removeFirst()) ?? height
    default: inputPath = arg
    }
}

guard !inputPath.isEmpty else {
    fputs("Usage: VulkanLDrawRenderer [--library <path>] [--color <code>] [--output <file.ppm>] [--width N] [--height N] <file.ldr|.dat|.mpd>\n", stderr)
    exit(1)
}

// MARK: - Load color table

let colorTable: LDrawColorTable
do {
    let cfgPath = ldConfigPath.isEmpty ? (ldrawLibPath + "/LDConfig.ldr") : ldConfigPath
    let cfgText = try String(contentsOfFile: cfgPath, encoding: .utf8)
    colorTable = try LDrawColorTable.parsing(ldConfigText: cfgText)
} catch {
    fputs("Warning: could not load LDConfig.ldr: \(error)\n", stderr)
    colorTable = LDrawColorTable()
}

let defaultColor = colorTable.color(forCode: Int16(colorCode))
    ?? LDrawResolvedColor(name: "Red", code: 4, red: 199, green: 20, blue: 20, edgeRed: 0, edgeGreen: 0, edgeBlue: 0)

// MARK: - Parse + resolve model

let inputURL = URL(fileURLWithPath: inputPath)
let searchDirs: [URL] = {
    var dirs: [URL] = [inputURL.deletingLastPathComponent()]
    if !ldrawLibPath.isEmpty {
        let base = URL(fileURLWithPath: ldrawLibPath)
        dirs += [
            base.appendingPathComponent("parts"),
            base.appendingPathComponent("parts/s"),
            base.appendingPathComponent("p"),
            base.appendingPathComponent("p/48"),
            base.appendingPathComponent("models"),
        ]
    }
    return dirs
}()

let resolver = FileSystemPartResolver(searchDirectories: searchDirs)
let modelResolver = LDrawModelResolver(resolver: resolver, missingPartPolicy: .omit)

let resolved: ResolvedLDrawModel
do {
    let text = try String(contentsOf: inputURL, encoding: .utf8)
    let parsed = try LDrawParser.parseMultiPartDocument(text)
    resolved = try modelResolver.resolve(parsed)
} catch {
    fputs("Error loading model: \(error)\n", stderr)
    exit(1)
}

// MARK: - Flatten to vertices

let flattener = LDrawVulkanFlattener(colorTable: colorTable, defaultColor: defaultColor)
let vertices = flattener.flatten(resolved)
guard !vertices.isEmpty else {
    fputs("Model produced no geometry.\n", stderr)
    exit(1)
}

var minP = Vector3(x: vertices[0].px, y: vertices[0].py, z: vertices[0].pz)
var maxP = minP
for v in vertices {
    let p = Vector3(x: v.px, y: v.py, z: v.pz)
    minP = Vector3(x: min(minP.x, p.x), y: min(minP.y, p.y), z: min(minP.z, p.z))
    maxP = Vector3(x: max(maxP.x, p.x), y: max(maxP.y, p.y), z: max(maxP.z, p.z))
}
let modelCenter = (minP + maxP) * 0.5
let modelRadius = (maxP - minP).length * 0.5

// MARK: - Render

guard let context = LDrawVulkanContext() else {
    fputs("Error: could not initialize Vulkan (is a Vulkan driver installed?)\n", stderr)
    exit(1)
}
guard let renderer = LDrawVulkanOffscreenRenderer(context: context, width: width, height: height) else {
    fputs("Error: could not create Vulkan renderer\n", stderr)
    exit(1)
}
renderer.modelCenter = modelCenter
renderer.modelRadius = modelRadius
renderer.distance = modelRadius * 3.5
renderer.upload(vertices: vertices)

let pixels = renderer.renderToRGBA()

// MARK: - Write PPM (PNG/ImageIO isn't available on Linux without extra deps)

func writePPM(rgba: [UInt8], width: Int, height: Int, to path: String) throws {
    var data = Data("P6\n\(width) \(height)\n255\n".utf8)
    data.reserveCapacity(data.count + width * height * 3)
    var rgb = [UInt8]()
    rgb.reserveCapacity(width * height * 3)
    for i in stride(from: 0, to: rgba.count, by: 4) {
        rgb.append(rgba[i])
        rgb.append(rgba[i + 1])
        rgb.append(rgba[i + 2])
    }
    data.append(contentsOf: rgb)
    try data.write(to: URL(fileURLWithPath: path))
}

do {
    try writePPM(rgba: pixels, width: width, height: height, to: outputPath)
    print("Wrote \(outputPath) (\(width)x\(height))")
} catch {
    fputs("Error writing output: \(error)\n", stderr)
    exit(1)
}

#else

print("VulkanLDrawRenderer is only supported on Linux.")

#endif
