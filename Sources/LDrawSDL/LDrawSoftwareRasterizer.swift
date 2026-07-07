import LegoDrawFile

/// A CPU triangle rasterizer with a real per-pixel depth buffer, producing an RGBA8
/// pixel buffer each frame. SDL3's 2D renderer (`SDLRenderer`) has no depth test of
/// its own, so a painter's-algorithm (depth-sorted triangle) approach — this
/// renderer's first cut — silently misorders overlapping/interpenetrating geometry
/// (e.g. a stud rising from a flat plate, whose depth ranges overlap the plate's
/// from most angles). A depth buffer resolves that per pixel, correctly, always.
///
/// Reuses its buffers across frames (resizing only when the viewport size changes)
/// to avoid a full allocation every frame.
final class LDrawSoftwareRasterizer {

    private(set) var width = 0
    private(set) var height = 0
    private var depthBuffer: [Float] = []
    /// RGBA8, row-major, 4 bytes per pixel.
    private(set) var colorBuffer: [UInt8] = []

    struct Lighting {
        var ambientIntensity: Float
        var keyLightDirection: Vector3
        var keyLightIntensity: Float
        var fillLightDirection: Vector3
        var fillLightIntensity: Float
    }

    /// Rasterizes `triangles` as seen by `camera` into `colorBuffer`, resizing
    /// buffers to `width`x`height` first if needed. Returns the finished buffer.
    @discardableResult
    func render(
        triangles: [LDrawWorldTriangle],
        camera: LDrawCamera,
        width: Int,
        height: Int,
        backgroundColor: (red: UInt8, green: UInt8, blue: UInt8),
        lighting: Lighting
    ) -> [UInt8] {
        resizeBuffersIfNeeded(width: width, height: height)
        clear(to: backgroundColor)

        let viewportWidth = Float(width)
        let viewportHeight = Float(height)

        for triangle in triangles {
            guard
                let p1 = camera.project(triangle.vertex1, viewportWidth: viewportWidth, viewportHeight: viewportHeight),
                let p2 = camera.project(triangle.vertex2, viewportWidth: viewportWidth, viewportHeight: viewportHeight),
                let p3 = camera.project(triangle.vertex3, viewportWidth: viewportWidth, viewportHeight: viewportHeight)
            else { continue }

            let normal = triangle.normal
            let key = max(0, normal.dot(-lighting.keyLightDirection)) * lighting.keyLightIntensity
            let fill = max(0, normal.dot(-lighting.fillLightDirection)) * lighting.fillLightIntensity
            let lightAmount = min(1, lighting.ambientIntensity + key + fill)

            let color = (
                r: UInt8(Float(triangle.color.red) * lightAmount),
                g: UInt8(Float(triangle.color.green) * lightAmount),
                b: UInt8(Float(triangle.color.blue) * lightAmount),
                a: triangle.color.alpha
            )

            rasterize(p1, p2, p3, color: color)
        }

        return colorBuffer
    }

    private func resizeBuffersIfNeeded(width: Int, height: Int) {
        guard width != self.width || height != self.height else { return }
        self.width = width
        self.height = height
        depthBuffer = [Float](repeating: .greatestFiniteMagnitude, count: width * height)
        colorBuffer = [UInt8](repeating: 0, count: width * height * 4)
    }

    private func clear(to backgroundColor: (red: UInt8, green: UInt8, blue: UInt8)) {
        for index in 0..<(width * height) {
            depthBuffer[index] = .greatestFiniteMagnitude
            let colorIndex = index * 4
            colorBuffer[colorIndex] = backgroundColor.red
            colorBuffer[colorIndex + 1] = backgroundColor.green
            colorBuffer[colorIndex + 2] = backgroundColor.blue
            colorBuffer[colorIndex + 3] = .max
        }
    }

    /// Scanline rasterization via edge functions (barycentric coordinates), with a
    /// linear (non-perspective-correct) depth interpolation — adequate for flat-shaded
    /// opaque part geometry, where every pixel of a triangle shares one color anyway.
    private func rasterize(
        _ p1: LDrawCamera.ProjectedPoint,
        _ p2: LDrawCamera.ProjectedPoint,
        _ p3: LDrawCamera.ProjectedPoint,
        color: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    ) {
        let minX = max(0, Int(min(p1.x, min(p2.x, p3.x)).rounded(.down)))
        let maxX = min(width - 1, Int(max(p1.x, max(p2.x, p3.x)).rounded(.up)))
        let minY = max(0, Int(min(p1.y, min(p2.y, p3.y)).rounded(.down)))
        let maxY = min(height - 1, Int(max(p1.y, max(p2.y, p3.y)).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }

        let area = edgeFunction(p1.x, p1.y, p2.x, p2.y, p3.x, p3.y)
        guard area != 0 else { return }
        let invArea = 1 / area

        for y in minY...maxY {
            let sampleY = Float(y) + 0.5
            let rowOffset = y * width
            for x in minX...maxX {
                let sampleX = Float(x) + 0.5

                let w0 = edgeFunction(p2.x, p2.y, p3.x, p3.y, sampleX, sampleY) * invArea
                let w1 = edgeFunction(p3.x, p3.y, p1.x, p1.y, sampleX, sampleY) * invArea
                let w2 = edgeFunction(p1.x, p1.y, p2.x, p2.y, sampleX, sampleY) * invArea
                guard w0 >= 0, w1 >= 0, w2 >= 0 else { continue }

                let depth = w0 * p1.depth + w1 * p2.depth + w2 * p3.depth
                let index = rowOffset + x
                guard depth < depthBuffer[index] else { continue }
                depthBuffer[index] = depth

                let colorIndex = index * 4
                colorBuffer[colorIndex] = color.r
                colorBuffer[colorIndex + 1] = color.g
                colorBuffer[colorIndex + 2] = color.b
                colorBuffer[colorIndex + 3] = color.a
            }
        }
    }

    private func edgeFunction(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float, _ cx: Float, _ cy: Float) -> Float {
        (cx - ax) * (by - ay) - (cy - ay) * (bx - ax)
    }
}
