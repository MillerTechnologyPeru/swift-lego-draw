import LegoDrawFile

/// Flattens a resolved LDraw model tree into a flat list of world-space triangles
/// (composing subfile transforms as it walks, resolving `currentColor`/`edgeColor`
/// references along the way), ready for a painter's-algorithm software rasterizer.
///
/// Quads are split into two triangles. Lines and optional/conditional lines are not
/// included — this renderer draws filled geometry only.
public struct LDrawSceneFlattener: Sendable {
    public var colorTable: LDrawColorTable
    public var defaultColor: LDrawResolvedColor

    public init(colorTable: LDrawColorTable, defaultColor: LDrawResolvedColor) {
        self.colorTable = colorTable
        self.defaultColor = defaultColor
    }

    public func flatten(_ model: ResolvedLDrawModel) -> [LDrawWorldTriangle] {
        var triangles: [LDrawWorldTriangle] = []
        flatten(model, transform: .identity, inheritedColor: defaultColor, into: &triangles)
        return triangles
    }

    private func flatten(
        _ model: ResolvedLDrawModel,
        transform: Matrix4,
        inheritedColor: LDrawResolvedColor,
        into triangles: inout [LDrawWorldTriangle]
    ) {
        for child in model.children {
            switch child {
            case .subfile(let childTransform, let color, _, let childModel):
                let childColor = resolveColor(color, current: inheritedColor)
                let combined = childTransform.multiplied(by: transform)
                flatten(childModel, transform: combined, inheritedColor: childColor, into: &triangles)

            case .missingSubfile:
                break

            case .triangle(let triangle):
                let color = resolveColor(triangle.color, current: inheritedColor)
                triangles.append(
                    LDrawWorldTriangle(
                        vertex1: transform.transformingPoint(triangle.vertex1),
                        vertex2: transform.transformingPoint(triangle.vertex2),
                        vertex3: transform.transformingPoint(triangle.vertex3),
                        color: color
                    )
                )

            case .quadrilateral(let quad):
                let color = resolveColor(quad.color, current: inheritedColor)
                let v1 = transform.transformingPoint(quad.vertex1)
                let v2 = transform.transformingPoint(quad.vertex2)
                let v3 = transform.transformingPoint(quad.vertex3)
                let v4 = transform.transformingPoint(quad.vertex4)
                triangles.append(LDrawWorldTriangle(vertex1: v1, vertex2: v2, vertex3: v3, color: color))
                triangles.append(LDrawWorldTriangle(vertex1: v1, vertex2: v3, vertex3: v4, color: color))

            case .line, .optionalLine:
                break
            }
        }
    }

    private func resolveColor(_ reference: LDrawColorReference, current: LDrawResolvedColor) -> LDrawResolvedColor {
        switch reference {
        case .currentColor:
            return current
        case .edgeColor:
            return LDrawResolvedColor(
                name: current.name + " Edge",
                code: current.code,
                red: current.edgeRed, green: current.edgeGreen, blue: current.edgeBlue, alpha: current.edgeAlpha,
                edgeRed: current.edgeRed, edgeGreen: current.edgeGreen, edgeBlue: current.edgeBlue, edgeAlpha: current.edgeAlpha,
                finish: .solid
            )
        case .index(let code):
            return colorTable.color(forCode: code) ?? current
        case .direct(let red, let green, let blue):
            return LDrawResolvedColor(
                name: "Direct",
                code: -1,
                red: red, green: green, blue: blue,
                edgeRed: red, edgeGreen: green, edgeBlue: blue
            )
        }
    }
}
