import SceneKit
import LegoDrawFile

/// Converts a resolved LDraw model tree into a SceneKit node graph: one `SCNNode`
/// per subfile instance (positioned via its transform), with each node's own direct
/// triangle/quad/line geometry merged per color into as few `SCNGeometry` objects
/// as practical.
///
/// Optional/conditional lines (line type 5) are not rendered with true view-dependent
/// visibility — that requires a custom shader modifier evaluating the control points
/// against the view transform per frame, which is left as a documented future
/// enhancement. By default they're built as hidden geometry (`isHidden = true`) so
/// callers can toggle them on if desired; see ``LDrawOptionalLineRenderingMode``.
///
/// Faces render double-sided unconditionally. BFC (back-face culling) winding is
/// still computed and used to orient each face's lighting normal, but single-sided
/// culling based on it is not enabled: getting the accumulated CERTIFY/INVERTNEXT/
/// mirrored-transform winding right for every face in every official part is a deep
/// rabbit hole, and a single wrong face silently disappears rather than failing loudly.
/// Double-sided rendering trades a minor, irrelevant-at-this-scale culling optimization
/// for guaranteeing complete geometry.
public struct LDrawSceneBuilder {

    public struct Options: Sendable {
        public var colorTable: LDrawColorTable
        public var defaultColor: LDrawResolvedColor
        public var optionalLineRendering: LDrawOptionalLineRenderingMode

        public init(
            colorTable: LDrawColorTable,
            defaultColor: LDrawResolvedColor,
            optionalLineRendering: LDrawOptionalLineRenderingMode = .hiddenByDefault
        ) {
            self.colorTable = colorTable
            self.defaultColor = defaultColor
            self.optionalLineRendering = optionalLineRendering
        }
    }

    private let options: Options
    private let materialCache = LDrawMaterialCache()

    public init(options: Options) {
        self.options = options
    }

    public func buildNode(from model: ResolvedLDrawModel) -> SCNNode {
        buildNode(
            from: model,
            inheritedColor: options.defaultColor,
            effectiveCCW: model.bfcState.windingIsCCW
        )
    }

    private func buildNode(
        from model: ResolvedLDrawModel,
        inheritedColor: LDrawResolvedColor,
        effectiveCCW: Bool
    ) -> SCNNode {
        let node = SCNNode()
        node.name = model.name

        var accumulator = LDrawGeometryAccumulator()

        for child in model.children {
            switch child {
            case .subfile(let transform, let color, let invertWinding, let childModel):
                let childColor = resolveColor(color, current: inheritedColor)
                let childNode = buildNode(
                    from: childModel,
                    inheritedColor: childColor,
                    effectiveCCW: invertWinding ? !effectiveCCW : effectiveCCW
                )
                childNode.transform = SCNMatrix4(transform)
                node.addChildNode(childNode)

            case .missingSubfile:
                break

            case .triangle(let triangle):
                accumulator.addTriangle(
                    triangle, resolvedColor: resolveColor(triangle.color, current: inheritedColor), ccw: effectiveCCW
                )

            case .quadrilateral(let quad):
                accumulator.addQuadrilateral(
                    quad, resolvedColor: resolveColor(quad.color, current: inheritedColor), ccw: effectiveCCW
                )

            case .line(let line):
                accumulator.addLine(line, resolvedColor: resolveColor(line.color, current: inheritedColor))

            case .optionalLine(let line):
                if options.optionalLineRendering != .omit {
                    accumulator.addOptionalLine(line, resolvedColor: resolveColor(line.color, current: inheritedColor))
                }
            }
        }

        for geometry in accumulator.makeFaceGeometries(materialCache: materialCache) {
            geometry.firstMaterial?.isDoubleSided = true
            node.addChildNode(SCNNode(geometry: geometry))
        }
        for geometry in accumulator.makeLineGeometries(materialCache: materialCache) {
            node.addChildNode(SCNNode(geometry: geometry))
        }
        if options.optionalLineRendering != .omit {
            let optionalLineGeometries = accumulator.makeOptionalLineGeometries(materialCache: materialCache)
            if !optionalLineGeometries.isEmpty {
                let optionalLinesNode = SCNNode()
                optionalLinesNode.isHidden = (options.optionalLineRendering == .hiddenByDefault)
                for geometry in optionalLineGeometries {
                    optionalLinesNode.addChildNode(SCNNode(geometry: geometry))
                }
                node.addChildNode(optionalLinesNode)
            }
        }

        return node
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
            return options.colorTable.color(forCode: code) ?? current
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
