import SceneKit
import LegoDrawFile

/// Accumulates a single `ResolvedLDrawModel` node's own direct geometry (not its
/// nested subfiles, which become separate child `SCNNode`s), merging faces and lines
/// per resolved color into one `SCNGeometry` each to minimize draw calls.
struct LDrawGeometryAccumulator {

    private var facePositionsByColor: [LDrawResolvedColor: [SCNVector3]] = [:]
    private var faceNormalsByColor: [LDrawResolvedColor: [SCNVector3]] = [:]
    private var faceIndicesByColor: [LDrawResolvedColor: [Int32]] = [:]

    private var linePositionsByColor: [LDrawResolvedColor: [SCNVector3]] = [:]
    private var optionalLinePositionsByColor: [LDrawResolvedColor: [SCNVector3]] = [:]

    mutating func addTriangle(_ triangle: LDrawTriangle, resolvedColor: LDrawResolvedColor, ccw: Bool) {
        addFace([triangle.vertex1, triangle.vertex2, triangle.vertex3], resolvedColor: resolvedColor, ccw: ccw)
    }

    mutating func addQuadrilateral(_ quad: LDrawQuadrilateral, resolvedColor: LDrawResolvedColor, ccw: Bool) {
        addFace(
            [quad.vertex1, quad.vertex2, quad.vertex3, quad.vertex4],
            resolvedColor: resolvedColor, ccw: ccw, isQuad: true
        )
    }

    mutating func addLine(_ line: LDrawLine, resolvedColor: LDrawResolvedColor) {
        linePositionsByColor[resolvedColor, default: []].append(contentsOf: [
            SCNVector3(line.start), SCNVector3(line.end),
        ])
    }

    mutating func addOptionalLine(_ line: LDrawOptionalLine, resolvedColor: LDrawResolvedColor) {
        optionalLinePositionsByColor[resolvedColor, default: []].append(contentsOf: [
            SCNVector3(line.start), SCNVector3(line.end),
        ])
    }

    private mutating func addFace(
        _ vertices: [Vector3], resolvedColor: LDrawResolvedColor, ccw: Bool, isQuad: Bool = false
    ) {
        let normal = SCNVector3(LDrawBFCNormalResolver.faceNormal(vertices, ccw: ccw))

        var positions = facePositionsByColor[resolvedColor] ?? []
        var normals = faceNormalsByColor[resolvedColor] ?? []
        var indices = faceIndicesByColor[resolvedColor] ?? []

        let baseIndex = Int32(positions.count)
        for vertex in vertices {
            positions.append(SCNVector3(vertex))
            normals.append(normal)
        }

        if isQuad {
            indices.append(contentsOf: [baseIndex, baseIndex + 1, baseIndex + 2, baseIndex, baseIndex + 2, baseIndex + 3])
        } else {
            indices.append(contentsOf: [baseIndex, baseIndex + 1, baseIndex + 2])
        }

        facePositionsByColor[resolvedColor] = positions
        faceNormalsByColor[resolvedColor] = normals
        faceIndicesByColor[resolvedColor] = indices
    }

    func makeFaceGeometries(materialCache: LDrawMaterialCache) -> [SCNGeometry] {
        facePositionsByColor.compactMap { color, positions in
            guard let normals = faceNormalsByColor[color], let indices = faceIndicesByColor[color] else { return nil }
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
            )
            geometry.materials = [materialCache.material(for: color)]
            return geometry
        }
    }

    func makeLineGeometries(materialCache: LDrawMaterialCache) -> [SCNGeometry] {
        Self.makeLineGeometries(from: linePositionsByColor, materialCache: materialCache)
    }

    func makeOptionalLineGeometries(materialCache: LDrawMaterialCache) -> [SCNGeometry] {
        Self.makeLineGeometries(from: optionalLinePositionsByColor, materialCache: materialCache)
    }

    private static func makeLineGeometries(
        from positionsByColor: [LDrawResolvedColor: [SCNVector3]], materialCache: LDrawMaterialCache
    ) -> [SCNGeometry] {
        positionsByColor.map { color, positions in
            let indices = Array(Int32(0)..<Int32(positions.count))
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: positions)],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .line)]
            )
            geometry.materials = [materialCache.material(for: color)]
            return geometry
        }
    }
}
