import SceneKit
import Testing
import LegoDrawFile
@testable import LDrawSceneKit

@Suite struct SceneBuildingTests {

    private func makeDefaultColor() -> LDrawResolvedColor {
        LDrawResolvedColor(
            name: "Current", code: 16,
            red: 128, green: 128, blue: 128,
            edgeRed: 51, edgeGreen: 51, edgeBlue: 51
        )
    }

    @Test func buildsNodeWithTriangleGeometry() {
        let triangle = LDrawTriangle(
            color: .index(4),
            vertex1: .zero,
            vertex2: Vector3(x: 1, y: 0, z: 0),
            vertex3: Vector3(x: 0, y: 1, z: 0)
        )
        let model = ResolvedLDrawModel(
            name: "leaf",
            bfcState: LDrawBFCState(isCertified: true, windingIsCCW: true),
            children: [.triangle(triangle)]
        )

        var colorTable = LDrawColorTable()
        colorTable.insert(
            LDrawResolvedColor(name: "Red", code: 4, red: 200, green: 0, blue: 0, edgeRed: 0, edgeGreen: 0, edgeBlue: 0)
        )

        let builder = LDrawSceneBuilder(options: .init(colorTable: colorTable, defaultColor: makeDefaultColor()))
        let node = builder.buildNode(from: model)

        let geometryNodes = node.childNodes.filter { $0.geometry != nil }
        #expect(geometryNodes.count == 1)
        #expect(geometryNodes.first?.geometry?.sources.first?.vectorCount == 3)
    }

    @Test func buildsNestedSubfileNodeWithCorrectTransform() {
        let leafModel = ResolvedLDrawModel(
            name: "leaf",
            bfcState: LDrawBFCState(isCertified: true),
            children: [
                .triangle(
                    LDrawTriangle(
                        color: .currentColor, vertex1: .zero,
                        vertex2: Vector3(x: 1, y: 0, z: 0), vertex3: Vector3(x: 0, y: 1, z: 0)
                    )
                )
            ]
        )
        let transform = Matrix4(
            a: 1, b: 0, c: 0, x: 10,
            d: 0, e: 1, f: 0, y: 20,
            g: 0, h: 0, i: 1, z: 30
        )
        let rootModel = ResolvedLDrawModel(
            name: "root",
            bfcState: LDrawBFCState(isCertified: true),
            children: [.subfile(transform: transform, color: .currentColor, invertWinding: false, model: leafModel)]
        )

        let builder = LDrawSceneBuilder(
            options: .init(colorTable: LDrawColorTable(), defaultColor: makeDefaultColor())
        )
        let node = builder.buildNode(from: rootModel)

        #expect(node.childNodes.count == 1)
        let childNode = node.childNodes[0]
        #expect(childNode.name == "leaf")
        #expect(abs(Float(childNode.transform.m41) - 10) < 0.0001)
        #expect(abs(Float(childNode.transform.m42) - 20) < 0.0001)
        #expect(abs(Float(childNode.transform.m43) - 30) < 0.0001)
    }

    @Test func missingSubfileProducesNoGeometry() {
        let model = ResolvedLDrawModel(
            name: "root",
            bfcState: LDrawBFCState(),
            children: [
                .missingSubfile(transform: .identity, color: .currentColor, fileName: "missing.dat")
            ]
        )
        let builder = LDrawSceneBuilder(
            options: .init(colorTable: LDrawColorTable(), defaultColor: makeDefaultColor())
        )
        let node = builder.buildNode(from: model)
        #expect(node.childNodes.isEmpty)
    }
}
