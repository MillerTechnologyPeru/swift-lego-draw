import LegoDrawFile

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
import Darwin
#endif

/// A simple look-at perspective camera used to project world-space points onto a
/// 2D viewport for the SDL software rasterizer. This is plain scalar math (no
/// matrix stack) since the renderer only ever needs to project points, not compose
/// transforms.
struct LDrawCamera {
    var eye: Vector3
    var target: Vector3
    var up: Vector3
    var fieldOfViewDegrees: Float
    var nearPlane: Float
    var farPlane: Float

    init(
        eye: Vector3,
        target: Vector3,
        up: Vector3 = Vector3(x: 0, y: 1, z: 0),
        fieldOfViewDegrees: Float = 35,
        nearPlane: Float = 1,
        farPlane: Float = 1_000_000
    ) {
        self.eye = eye
        self.target = target
        self.up = up
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.nearPlane = nearPlane
        self.farPlane = farPlane
    }

    struct ProjectedPoint {
        var x: Float
        var y: Float
        /// Camera-relative depth (larger = farther), used for the rasterizer's z-test.
        var depth: Float
    }

    /// Projects a world-space point to viewport pixel coordinates plus a
    /// camera-relative depth, or `nil` if the point is behind or too close to the
    /// camera to project meaningfully.
    ///
    /// - Note: There is no near-plane clipping — a triangle with any vertex that
    ///   fails to project is dropped whole by the caller. Fine for the typical
    ///   case of a camera orbiting outside a part/model's bounding sphere; a
    ///   triangle straddling the camera itself will simply vanish.
    func project(_ point: Vector3, viewportWidth: Float, viewportHeight: Float) -> ProjectedPoint? {
        let forward = (target - eye).normalized
        let right = forward.cross(up).normalized
        let trueUp = right.cross(forward)

        let relative = point - eye
        let viewX = relative.dot(right)
        let viewY = relative.dot(trueUp)
        let viewZ = relative.dot(forward)

        guard viewZ > nearPlane, viewZ < farPlane else { return nil }

        let fovRadians = fieldOfViewDegrees * .pi / 180
        let tanHalfFov = tan(fovRadians / 2)
        let aspectRatio = viewportWidth / max(viewportHeight, 1)

        let ndcX = viewX / (viewZ * tanHalfFov * aspectRatio)
        let ndcY = viewY / (viewZ * tanHalfFov)

        // NDC (-1...1, Y up) to pixel coordinates (0...size, Y down).
        let pixelX = (ndcX * 0.5 + 0.5) * viewportWidth
        let pixelY = (1 - (ndcY * 0.5 + 0.5)) * viewportHeight

        return ProjectedPoint(x: pixelX, y: pixelY, depth: viewZ)
    }
}
