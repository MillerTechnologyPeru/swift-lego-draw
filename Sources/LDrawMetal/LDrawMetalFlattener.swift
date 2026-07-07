#if canImport(Metal)
import simd
import LegoDrawFile

/// Walks a ``ResolvedLDrawModel`` tree and emits a flat ``[LDrawMetalVertex]``
/// array (every 3 vertices = one triangle) suitable for a Metal vertex buffer.
public struct LDrawMetalFlattener {

    private let colorTable: LDrawColorTable
    private let defaultColor: LDrawResolvedColor

    public init(colorTable: LDrawColorTable, defaultColor: LDrawResolvedColor) {
        self.colorTable = colorTable
        self.defaultColor = defaultColor
    }

    public func flatten(_ model: ResolvedLDrawModel) -> [LDrawMetalVertex] {
        var vertices: [LDrawMetalVertex] = []
        visit(
            model,
            transform: matrix_identity_float4x4,
            inheritedColor: defaultColor,
            ccw: model.bfcState.windingIsCCW,
            &vertices
        )
        return vertices
    }

    // MARK: - Private

    private func visit(
        _ model: ResolvedLDrawModel,
        transform: float4x4,
        inheritedColor: LDrawResolvedColor,
        ccw: Bool,
        _ out: inout [LDrawMetalVertex]
    ) {
        for child in model.children {
            switch child {
            case .subfile(let t, let colorRef, let invertWinding, let sub):
                let childTransform = transform * float4x4(t)
                let childColor = resolve(colorRef, current: inheritedColor)
                let childCCW = invertWinding ? !ccw : ccw
                visit(sub, transform: childTransform, inheritedColor: childColor, ccw: childCCW, &out)

            case .triangle(let tri):
                let color = resolve(tri.color, current: inheritedColor)
                addTriangle(
                    v0: tri.vertex1, v1: tri.vertex2, v2: tri.vertex3,
                    color: color, transform: transform, ccw: ccw, &out
                )

            case .quadrilateral(let quad):
                let color = resolve(quad.color, current: inheritedColor)
                addTriangle(
                    v0: quad.vertex1, v1: quad.vertex2, v2: quad.vertex3,
                    color: color, transform: transform, ccw: ccw, &out
                )
                addTriangle(
                    v0: quad.vertex1, v1: quad.vertex3, v2: quad.vertex4,
                    color: color, transform: transform, ccw: ccw, &out
                )

            case .line, .optionalLine, .missingSubfile:
                break
            }
        }
    }

    private func addTriangle(
        v0: Vector3, v1: Vector3, v2: Vector3,
        color: LDrawResolvedColor,
        transform: float4x4,
        ccw: Bool,
        _ out: inout [LDrawMetalVertex]
    ) {
        let p0 = transformPoint(v0, by: transform)
        let p1 = transformPoint(v1, by: transform)
        let p2 = transformPoint(v2, by: transform)

        let edge1 = p1 - p0
        let edge2 = p2 - p0
        var normal = simd_normalize(simd_cross(edge1, edge2))
        if !ccw { normal = -normal }

        let c = SIMD4<Float>(
            Float(color.red) / 255, Float(color.green) / 255,
            Float(color.blue) / 255, Float(color.alpha) / 255
        )

        // Emit double-sided: front then back (reversed winding)
        out.append(LDrawMetalVertex(position: p0, normal: normal, color: c))
        out.append(LDrawMetalVertex(position: p1, normal: normal, color: c))
        out.append(LDrawMetalVertex(position: p2, normal: normal, color: c))
        out.append(LDrawMetalVertex(position: p0, normal: -normal, color: c))
        out.append(LDrawMetalVertex(position: p2, normal: -normal, color: c))
        out.append(LDrawMetalVertex(position: p1, normal: -normal, color: c))
    }

    private func transformPoint(_ v: Vector3, by m: float4x4) -> SIMD3<Float> {
        let p = m * SIMD4<Float>(v.x, v.y, v.z, 1)
        return SIMD3<Float>(p.x, p.y, p.z)
    }

    private func resolve(_ ref: LDrawColorReference, current: LDrawResolvedColor) -> LDrawResolvedColor {
        switch ref {
        case .currentColor: return current
        case .edgeColor:
            return LDrawResolvedColor(
                name: current.name + " Edge", code: current.code,
                red: current.edgeRed, green: current.edgeGreen, blue: current.edgeBlue, alpha: current.edgeAlpha,
                edgeRed: current.edgeRed, edgeGreen: current.edgeGreen, edgeBlue: current.edgeBlue, edgeAlpha: current.edgeAlpha,
                finish: .solid
            )
        case .index(let code):
            return colorTable.color(forCode: code) ?? current
        case .direct(let r, let g, let b):
            return LDrawResolvedColor(name: "Direct", code: -1,
                red: r, green: g, blue: b,
                edgeRed: r, edgeGreen: g, edgeBlue: b)
        }
    }
}

// MARK: - float4x4 from Matrix4

private extension float4x4 {
    init(_ m: Matrix4) {
        self.init(columns: (
            SIMD4<Float>(m.a, m.d, m.g, 0),
            SIMD4<Float>(m.b, m.e, m.h, 0),
            SIMD4<Float>(m.c, m.f, m.i, 0),
            SIMD4<Float>(m.x, m.y, m.z, 1)
        ))
    }
}
#endif
