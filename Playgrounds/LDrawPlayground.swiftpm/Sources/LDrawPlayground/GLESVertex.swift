import simd
import LegoDrawFile

/// Packed vertex for OpenGL ES — no SIMD alignment padding, stride = 40 bytes.
struct GLESVertex {
    var px, py, pz: Float   // position  (offset  0)
    var nx, ny, nz: Float   // normal    (offset 12)
    var r, g, b, a: Float   // color     (offset 24)
}

/// Walks a ``ResolvedLDrawModel`` and emits a flat ``[GLESVertex]`` array
/// (every 3 vertices = one triangle) for upload to an OpenGL ES VBO.
struct LDrawGLESFlattener {

    private let colorTable: LDrawColorTable
    private let defaultColor: LDrawResolvedColor

    init(colorTable: LDrawColorTable, defaultColor: LDrawResolvedColor) {
        self.colorTable = colorTable
        self.defaultColor = defaultColor
    }

    func flatten(_ model: ResolvedLDrawModel) -> [GLESVertex] {
        var vertices: [GLESVertex] = []
        visit(model, transform: matrix_identity_float4x4,
              inheritedColor: defaultColor, ccw: model.bfcState.windingIsCCW, &vertices)
        return vertices
    }

    // MARK: - Private

    private func visit(
        _ model: ResolvedLDrawModel,
        transform: float4x4,
        inheritedColor: LDrawResolvedColor,
        ccw: Bool,
        _ out: inout [GLESVertex]
    ) {
        for child in model.children {
            switch child {
            case .subfile(let t, let colorRef, let invertWinding, let sub):
                visit(sub,
                      transform: transform * float4x4(t),
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
        transform: float4x4,
        ccw: Bool,
        _ out: inout [GLESVertex]
    ) {
        let p0 = tp(v0, transform)
        let p1 = tp(v1, transform)
        let p2 = tp(v2, transform)
        var n = simd_normalize(simd_cross(p1 - p0, p2 - p0))
        if !ccw { n = -n }
        let r = Float(color.red)   / 255
        let g = Float(color.green) / 255
        let b = Float(color.blue)  / 255
        let a = Float(color.alpha) / 255
        // Emit both windings for double-sided rendering
        out.append(GLESVertex(px: p0.x, py: p0.y, pz: p0.z, nx: n.x, ny: n.y, nz: n.z, r: r, g: g, b: b, a: a))
        out.append(GLESVertex(px: p1.x, py: p1.y, pz: p1.z, nx: n.x, ny: n.y, nz: n.z, r: r, g: g, b: b, a: a))
        out.append(GLESVertex(px: p2.x, py: p2.y, pz: p2.z, nx: n.x, ny: n.y, nz: n.z, r: r, g: g, b: b, a: a))
        out.append(GLESVertex(px: p0.x, py: p0.y, pz: p0.z, nx: -n.x, ny: -n.y, nz: -n.z, r: r, g: g, b: b, a: a))
        out.append(GLESVertex(px: p2.x, py: p2.y, pz: p2.z, nx: -n.x, ny: -n.y, nz: -n.z, r: r, g: g, b: b, a: a))
        out.append(GLESVertex(px: p1.x, py: p1.y, pz: p1.z, nx: -n.x, ny: -n.y, nz: -n.z, r: r, g: g, b: b, a: a))
    }

    private func tp(_ v: Vector3, _ m: float4x4) -> SIMD3<Float> {
        let p = m * SIMD4<Float>(v.x, v.y, v.z, 1)
        return SIMD3<Float>(p.x, p.y, p.z)
    }

    private func resolve(_ ref: LDrawColorReference, current: LDrawResolvedColor) -> LDrawResolvedColor {
        switch ref {
        case .currentColor: return current
        case .edgeColor:
            return LDrawResolvedColor(
                name: current.name + " Edge", code: current.code,
                red: current.edgeRed, green: current.edgeGreen,
                blue: current.edgeBlue, alpha: current.edgeAlpha,
                edgeRed: current.edgeRed, edgeGreen: current.edgeGreen,
                edgeBlue: current.edgeBlue, edgeAlpha: current.edgeAlpha,
                finish: .solid)
        case .index(let code):
            return colorTable.color(forCode: code) ?? current
        case .direct(let r, let g, let b):
            return LDrawResolvedColor(name: "Direct", code: -1,
                red: r, green: g, blue: b, edgeRed: r, edgeGreen: g, edgeBlue: b)
        }
    }
}

// MARK: - float4x4 from LegoDrawFile Matrix4

extension float4x4 {
    init(_ m: Matrix4) {
        self.init(columns: (
            SIMD4<Float>(m.a, m.d, m.g, 0),
            SIMD4<Float>(m.b, m.e, m.h, 0),
            SIMD4<Float>(m.c, m.f, m.i, 0),
            SIMD4<Float>(m.x, m.y, m.z, 1)
        ))
    }
}
