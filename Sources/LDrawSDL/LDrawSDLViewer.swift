import CSDL3
import LegoDrawFile
import SDL3Swift

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
import Darwin
#endif

/// A minimal interactive 3D LDraw viewer built on SDL3: world-space triangles are
/// rasterized by `LDrawSoftwareRasterizer` (a CPU rasterizer with a real per-pixel
/// depth buffer — SDL's 2D renderer has none of its own) into an RGBA8 buffer,
/// shaded with a two-light-plus-ambient model, then uploaded to a streaming
/// `SDLTexture` and blitted full-window each frame.
///
/// Edge lines (LDraw line types 2/5) are not drawn yet.
public struct LDrawSDLViewer {

    public struct Options: Sendable {
        public var windowTitle: String
        public var windowSize: (width: Int, height: Int)
        public var backgroundColor: (red: UInt8, green: UInt8, blue: UInt8)
        public var autoRotate: Bool
        public var ambientIntensity: Float
        public var keyLightDirection: Vector3
        public var keyLightIntensity: Float
        public var fillLightDirection: Vector3
        public var fillLightIntensity: Float

        public init(
            windowTitle: String = "LDraw Viewer",
            windowSize: (width: Int, height: Int) = (1024, 768),
            backgroundColor: (red: UInt8, green: UInt8, blue: UInt8) = (245, 245, 245),
            autoRotate: Bool = true,
            ambientIntensity: Float = 0.4,
            keyLightDirection: Vector3 = Vector3(x: -0.4, y: -0.8, z: -0.4).normalized,
            keyLightIntensity: Float = 0.65,
            fillLightDirection: Vector3 = Vector3(x: 0.5, y: 0.15, z: 0.55).normalized,
            fillLightIntensity: Float = 0.3
        ) {
            self.windowTitle = windowTitle
            self.windowSize = windowSize
            self.backgroundColor = backgroundColor
            self.autoRotate = autoRotate
            self.ambientIntensity = ambientIntensity
            self.keyLightDirection = keyLightDirection
            self.keyLightIntensity = keyLightIntensity
            self.fillLightDirection = fillLightDirection
            self.fillLightIntensity = fillLightIntensity
        }

        var lighting: LDrawSoftwareRasterizer.Lighting {
            .init(
                ambientIntensity: ambientIntensity,
                keyLightDirection: keyLightDirection,
                keyLightIntensity: keyLightIntensity,
                fillLightDirection: fillLightDirection,
                fillLightIntensity: fillLightIntensity
            )
        }
    }

    private let triangles: [LDrawWorldTriangle]
    private let options: Options

    public init(triangles: [LDrawWorldTriangle], options: Options = Options()) {
        self.triangles = triangles
        self.options = options
    }

    /// Opens a window and runs the event/render loop until the window is closed or
    /// Escape is pressed. Blocks the calling thread.
    public func run() throws(SDLError) {
        try SDL.initialize(subSystems: [.video])
        defer { SDL.quit() }

        let window = try SDLWindow(
            title: options.windowTitle,
            frame: (x: .centered, y: .centered, width: options.windowSize.width, height: options.windowSize.height),
            options: [.resizable, .highPixelDensity]
        )
        let renderer = try SDLRenderer(window: window)
        let rasterizer = LDrawSoftwareRasterizer()
        var frameTexture: SDLTexture?
        var frameTextureSize: (width: Int, height: Int) = (0, 0)

        let target = triangles.boundsCenter
        let distance = triangles.boundsRadius * 2.8
        var yaw: Float = 0.6
        var pitch: Float = 0.35

        var isDragging = false
        var lastMouse: (x: Float, y: Float) = (0, 0)
        var running = true

        while running {
            while let event = SDL.pollEvent() {
                switch event {
                case .quit:
                    running = false

                case .keyDown(let scancode, _):
                    if scancode.rawValue == UInt32(SDL_SCANCODE_ESCAPE.rawValue) {
                        running = false
                    }

                case .mouseButtonDown(_, let x, let y, let button):
                    if button == .left {
                        isDragging = true
                        lastMouse = (x, y)
                    }

                case .mouseButtonUp(_, _, _, let button):
                    if button == .left {
                        isDragging = false
                    }

                case .mouseMotion(_, let x, let y, _):
                    if isDragging {
                        yaw += (x - lastMouse.x) * 0.01
                        pitch = max(-1.5, min(1.5, pitch - (y - lastMouse.y) * 0.01))
                        lastMouse = (x, y)
                    }

                default:
                    break
                }
            }

            if options.autoRotate && !isDragging {
                yaw += 0.006
            }

            let eye = target + Vector3(
                x: distance * cos(pitch) * sin(yaw),
                y: distance * sin(pitch),
                z: distance * cos(pitch) * cos(yaw)
            )
            let camera = LDrawCamera(eye: eye, target: target)

            try drawFrame(
                camera: camera, window: window, renderer: renderer, rasterizer: rasterizer,
                frameTexture: &frameTexture, frameTextureSize: &frameTextureSize
            )
        }
    }

    private func drawFrame(
        camera: LDrawCamera,
        window: SDLWindow,
        renderer: SDLRenderer,
        rasterizer: LDrawSoftwareRasterizer,
        frameTexture: inout SDLTexture?,
        frameTextureSize: inout (width: Int, height: Int)
    ) throws(SDLError) {
        let size = window.drawableSize
        guard size.width > 0, size.height > 0 else { return }

        rasterizer.render(
            triangles: triangles,
            camera: camera,
            width: size.width,
            height: size.height,
            backgroundColor: options.backgroundColor,
            lighting: options.lighting
        )

        if frameTexture == nil || frameTextureSize.width != size.width || frameTextureSize.height != size.height {
            frameTexture = try SDLTexture(
                renderer: renderer,
                format: SDLPixelFormat.Format(rawValue: SDL_PIXELFORMAT_RGBA8888.rawValue),
                access: .streaming,
                width: size.width,
                height: size.height
            )
            try frameTexture?.setScaleMode(.nearest)
            frameTextureSize = size
        }

        guard let texture = frameTexture else { return }

        let colorBuffer = rasterizer.colorBuffer
        let rowBytes = size.width * 4
        colorBuffer.withUnsafeBytes { source in
            _ = try? texture.withUnsafeMutableBytes { destination, pitch in
                if pitch == rowBytes {
                    destination.copyMemory(from: source.baseAddress!, byteCount: source.count)
                } else {
                    for row in 0..<size.height {
                        let sourceRow = source.baseAddress!.advanced(by: row * rowBytes)
                        let destinationRow = destination.advanced(by: row * pitch)
                        destinationRow.copyMemory(from: sourceRow, byteCount: rowBytes)
                    }
                }
            }
        }

        try renderer.copy(texture, destination: SDL_FRect(x: 0, y: 0, w: Float(size.width), h: Float(size.height)))
        renderer.present()
    }
}
