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

/// A minimal interactive 3D LDraw viewer built on SDL3's 2D renderer: world-space
/// triangles are projected with a software perspective camera, depth-sorted
/// back-to-front (a painter's algorithm — SDL's 2D renderer has no depth buffer),
/// flat-shaded with a single directional light, and rasterized via
/// `SDLRenderer.drawGeometry`. Edge lines (LDraw line types 2/5) are not drawn yet.
public struct LDrawSDLViewer {

    public struct Options: Sendable {
        public var windowTitle: String
        public var windowSize: (width: Int, height: Int)
        public var backgroundColor: (red: UInt8, green: UInt8, blue: UInt8)
        public var autoRotate: Bool
        public var lightDirection: Vector3

        public init(
            windowTitle: String = "LDraw Viewer",
            windowSize: (width: Int, height: Int) = (1024, 768),
            backgroundColor: (red: UInt8, green: UInt8, blue: UInt8) = (245, 245, 245),
            autoRotate: Bool = true,
            lightDirection: Vector3 = Vector3(x: -0.4, y: -0.8, z: -0.4).normalized
        ) {
            self.windowTitle = windowTitle
            self.windowSize = windowSize
            self.backgroundColor = backgroundColor
            self.autoRotate = autoRotate
            self.lightDirection = lightDirection
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

            try drawFrame(camera: camera, window: window, renderer: renderer)
        }
    }

    private func drawFrame(camera: LDrawCamera, window: SDLWindow, renderer: SDLRenderer) throws(SDLError) {
        let size = window.drawableSize
        let width = Float(size.width)
        let height = Float(size.height)

        struct ProjectedTriangle {
            var points: [(x: Float, y: Float)]
            var depth: Float
            var color: SDLRenderer.VertexColor
        }

        var projected: [ProjectedTriangle] = []
        projected.reserveCapacity(triangles.count)

        for triangle in triangles {
            guard
                let p1 = camera.project(triangle.vertex1, viewportWidth: width, viewportHeight: height),
                let p2 = camera.project(triangle.vertex2, viewportWidth: width, viewportHeight: height),
                let p3 = camera.project(triangle.vertex3, viewportWidth: width, viewportHeight: height)
            else { continue }

            let lightAmount = max(0.3, triangle.normal.dot(-options.lightDirection))
            let color = SDLRenderer.VertexColor(
                red: Float(triangle.color.red) / 255 * lightAmount,
                green: Float(triangle.color.green) / 255 * lightAmount,
                blue: Float(triangle.color.blue) / 255 * lightAmount,
                alpha: Float(triangle.color.alpha) / 255
            )
            let depth = (p1.depth + p2.depth + p3.depth) / 3
            projected.append(ProjectedTriangle(points: [(p1.x, p1.y), (p2.x, p2.y), (p3.x, p3.y)], depth: depth, color: color))
        }

        // Painter's algorithm: draw farthest triangles first so nearer ones overdraw them.
        projected.sort { $0.depth > $1.depth }

        try renderer.setDrawColor(red: options.backgroundColor.red, green: options.backgroundColor.green, blue: options.backgroundColor.blue)
        try renderer.clear()

        if !projected.isEmpty {
            var vertices: [(position: SDL_FPoint, color: SDLRenderer.VertexColor)] = []
            vertices.reserveCapacity(projected.count * 3)
            for triangle in projected {
                for point in triangle.points {
                    vertices.append((SDL_FPoint(x: point.x, y: point.y), triangle.color))
                }
            }
            try renderer.drawGeometry(vertices: vertices)
        }

        renderer.present()
    }
}
