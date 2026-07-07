import AppKit
import MetalKit
import simd
import LegoDrawFile
import LDrawMetal

// MARK: - CLI args

var ldrawLibPath: String = ProcessInfo.processInfo.environment["LDRAWDIR"] ?? ""
var ldConfigPath: String = ""
var colorCode: Int = 4   // red
var inputPath: String = ""

var args = CommandLine.arguments.dropFirst()
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--library": ldrawLibPath = args.removeFirst()
    case "--ldconfig": ldConfigPath = args.removeFirst()
    case "--color": colorCode = Int(args.removeFirst()) ?? colorCode
    default: inputPath = arg
    }
}

guard !inputPath.isEmpty else {
    fputs("Usage: MetalLDrawViewer [--library <path>] [--color <code>] <file.ldr|.dat|.mpd>\n", stderr)
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

let flattener = LDrawMetalFlattener(colorTable: colorTable, defaultColor: defaultColor)
let vertices = flattener.flatten(resolved)
guard !vertices.isEmpty else {
    fputs("Model produced no geometry.\n", stderr)
    exit(1)
}

// Bounding sphere for camera distance
var minP = vertices[0].position, maxP = vertices[0].position
for v in vertices {
    minP = simd_min(minP, v.position)
    maxP = simd_max(maxP, v.position)
}
let modelRadius = simd_length(maxP - minP) * 0.5

// MARK: - OrbitView

final class OrbitView: MTKView {
    weak var renderer: LDrawMetalRenderer?
    var lastDrag: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        lastDrag = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = event.locationInWindow
        let dx = Float(loc.x - lastDrag.x) * 0.005
        let dy = Float(loc.y - lastDrag.y) * 0.005
        lastDrag = loc
        renderer?.azimuth  += dx
        renderer?.elevation = max(-1.4, min(1.4, (renderer?.elevation ?? 0) + dy))
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY)
        if let r = renderer {
            r.distance = max(r.modelRadius * 0.5, r.distance - delta * r.modelRadius * 0.02)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) }  // Escape
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Launch

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSMakeRect(0, 0, 900, 700),
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered,
    defer: false
)
window.title = inputURL.lastPathComponent
window.center()

guard let device = MTLCreateSystemDefaultDevice() else {
    fputs("Metal not available.\n", stderr)
    exit(1)
}

let orbitView = OrbitView(frame: window.contentView!.bounds, device: device)
orbitView.autoresizingMask = [.width, .height]
orbitView.depthStencilPixelFormat = .depth32Float
orbitView.colorPixelFormat = .bgra8Unorm
orbitView.preferredFramesPerSecond = 60

guard let renderer = LDrawMetalRenderer(mtkView: orbitView) else {
    fputs("Could not create Metal renderer.\n", stderr)
    exit(1)
}
renderer.modelCenter = (minP + maxP) * 0.5
renderer.distance = modelRadius * 3.5
renderer.modelRadius = modelRadius
renderer.upload(vertices: vertices)
orbitView.renderer = renderer

window.contentView?.addSubview(orbitView)

let delegate = AppDelegate()
app.delegate = delegate
window.makeKeyAndOrderFront(nil)
orbitView.window?.makeFirstResponder(orbitView)

// Auto-rotate
Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
    renderer.azimuth += 0.005
}

app.run()
