#if os(Linux) || os(Android)
import LegoDrawFile

/// Walks a ``ResolvedLDrawModel`` tree and emits a flat ``[LDrawVulkanVertex]``
/// array (every 3 vertices = one triangle) for upload to a Vulkan vertex
/// buffer. Uses ``Vector3``/``Matrix4`` from LegoDrawFile rather than `simd`,
/// since `simd` is unavailable on Linux.
public struct LDrawVulkanFlattener {

    private let colorTable: LDrawColorTable
    private let defaultColor: LDrawResolvedColor

    public init(colorTable: LDrawColorTable, defaultColor: LDrawResolvedColor) {
        self.colorTable = colorTable
        self.defaultColor = defaultColor
    }

    public func flatten(_ model: ResolvedLDrawModel) -> [LDrawVulkanVertex] {
        var vertices: [LDrawVulkanVertex] = []
        visit(model, transform: .identity, inheritedColor: defaultColor,
              ccw: model.bfcState.windingIsCCW, &vertices)
        return vertices
    }

    // MARK: - Private

    private func visit(
        _ model: ResolvedLDrawModel,
        transform: Matrix4,
        inheritedColor: LDrawResolvedColor,
        ccw: Bool,
        _ out: inout [LDrawVulkanVertex]
    ) {
        for child in model.children {
            switch child {
            case .subfile(let t, let colorRef, let invertWinding, let sub):
                // Apply the subfile's own local transform `t` first (child-local -> parent-local),
                // then the already-accumulated `transform` (parent-local -> world) — i.e. compose
                // as `t` then `transform`, which per `multiplied(by:)`'s "self first, then other"
                // convention is `t.multiplied(by: transform)`.
                visit(sub,
                      transform: t.multiplied(by: transform),
                      inheritedColor: resolve(colorRef, current: inheritedColor),
                      ccw: invertWinding ? !ccw : ccw,
                      &out)

            case .triangle(let tri):
                let c = resolve(tri.color, current: inheritedColor)
                addTriangle(tri.vertex1, tri.vertex2, tri.vertex3,
                            color: c, transform: transform, ccw: ccw, &out)

            case .quadrilateral(let quad):
                let c = resolve(quad.color, current: inheritedColor)
                addTriangle(quad.vertex1, quad.vertex2, quad.vertex3,
                            color: c, transform: transform, ccw: ccw, &out)
                addTriangle(quad.vertex1, quad.vertex3, quad.vertex4,
                            color: c, transform: transform, ccw: ccw, &out)

            case .line, .optionalLine, .missingSubfile:
                break
            }
        }
    }

    private func addTriangle(
        _ v0: Vector3, _ v1: Vector3, _ v2: Vector3,
        color: LDrawResolvedColor,
        transform: Matrix4,
        ccw: Bool,
        _ out: inout [LDrawVulkanVertex]
    ) {
        let p0 = transform.transformingPoint(v0)
        let p1 = transform.transformingPoint(v1)
        let p2 = transform.transformingPoint(v2)

        var n = (p1 - p0).cross(p2 - p0).normalized
        if !ccw { n = -n }

        let r = Float(color.red)   / 255
        let g = Float(color.green) / 255
        let b = Float(color.blue)  / 255
        let a = Float(color.alpha) / 255

        // Emit both windings for double-sided rendering.
        out.append(LDrawVulkanVertex(px: p0.x, py: p0.y, pz: p0.z, nx: n.x, ny: n.y, nz: n.z, r: r, g: g, b: b, a: a))
        out.append(LDrawVulkanVertex(px: p1.x, py: p1.y, pz: p1.z, nx: n.x, ny: n.y, nz: n.z, r: r, g: g, b: b, a: a))
        out.append(LDrawVulkanVertex(px: p2.x, py: p2.y, pz: p2.z, nx: n.x, ny: n.y, nz: n.z, r: r, g: g, b: b, a: a))
        out.append(LDrawVulkanVertex(px: p0.x, py: p0.y, pz: p0.z, nx: -n.x, ny: -n.y, nz: -n.z, r: r, g: g, b: b, a: a))
        out.append(LDrawVulkanVertex(px: p2.x, py: p2.y, pz: p2.z, nx: -n.x, ny: -n.y, nz: -n.z, r: r, g: g, b: b, a: a))
        out.append(LDrawVulkanVertex(px: p1.x, py: p1.y, pz: p1.z, nx: -n.x, ny: -n.y, nz: -n.z, r: r, g: g, b: b, a: a))
    }

    private func resolve(_ ref: LDrawColorReference, current: LDrawResolvedColor) -> LDrawResolvedColor {
        switch ref {
        case .currentColor: return current
        case .edgeColor:
            return LDrawResolvedColor(
                name: current.name + " Edge", code: current.code,
                red: current.edgeRed, green: current.edgeGreen, blue: current.edgeBlue, alpha: current.edgeAlpha,
                edgeRed: current.edgeRed, edgeGreen: current.edgeGreen, edgeBlue: current.edgeBlue, edgeAlpha: current.edgeAlpha,
                finish: .solid)
        case .index(let code):
            return colorTable.color(forCode: code) ?? current
        case .direct(let r, let g, let b):
            return LDrawResolvedColor(name: "Direct", code: -1,
                red: r, green: g, blue: b, edgeRed: r, edgeGreen: g, edgeBlue: b)
        }
    }
}
#endif
