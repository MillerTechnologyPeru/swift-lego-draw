import SceneKit
import Testing
import LegoDrawFile
@testable import LDrawSceneKit

@Suite struct MaterialCacheTests {

    private func makeColor(code: Int16 = 4, alpha: UInt8 = 255) -> LDrawResolvedColor {
        LDrawResolvedColor(
            name: "Red", code: code,
            red: 200, green: 20, blue: 20, alpha: alpha,
            edgeRed: 50, edgeGreen: 50, edgeBlue: 50
        )
    }

    @Test func sameColorReturnsIdenticalMaterialInstance() {
        let cache = LDrawMaterialCache()
        let color = makeColor()
        let material1 = cache.material(for: color)
        let material2 = cache.material(for: color)
        #expect(material1 === material2)
    }

    @Test func distinctColorsReturnDistinctMaterials() {
        let cache = LDrawMaterialCache()
        let material1 = cache.material(for: makeColor(code: 4))
        let material2 = cache.material(for: makeColor(code: 5))
        #expect(material1 !== material2)
    }

    @Test func transparentColorSetsAlphaBlendMode() {
        let cache = LDrawMaterialCache()
        let material = cache.material(for: makeColor(alpha: 128))
        #expect(material.blendMode == .alpha)
        #expect(material.isDoubleSided == true)
    }

    @Test func opaqueColorDoesNotForceDoubleSided() {
        let cache = LDrawMaterialCache()
        let material = cache.material(for: makeColor(alpha: 255))
        #expect(material.isDoubleSided == false)
    }
}
