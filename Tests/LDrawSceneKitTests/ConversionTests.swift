import SceneKit
import Testing
import LegoDrawFile
@testable import LDrawSceneKit

@Suite struct ConversionTests {

    @Test func vector3ConvertsToSCNVector3() {
        let v = Vector3(x: 1.5, y: -2.5, z: 3.0)
        let scn = SCNVector3(v)
        #expect(abs(Float(scn.x) - v.x) < 0.0001)
        #expect(abs(Float(scn.y) - v.y) < 0.0001)
        #expect(abs(Float(scn.z) - v.z) < 0.0001)
    }

    @Test func matrix4ConvertsToSCNMatrix4PreservingTranslation() {
        let m = Matrix4(
            a: 1, b: 0, c: 0, x: 10,
            d: 0, e: 1, f: 0, y: 20,
            g: 0, h: 0, i: 1, z: 30
        )
        let scn = SCNMatrix4(m)
        #expect(abs(Float(scn.m41) - 10) < 0.0001)
        #expect(abs(Float(scn.m42) - 20) < 0.0001)
        #expect(abs(Float(scn.m43) - 30) < 0.0001)
    }

    @Test func matrix4ConversionPreservesRotationComponents() {
        let m = Matrix4(
            a: 0, b: -1, c: 0, x: 5,
            d: 1, e: 0, f: 0, y: 6,
            g: 0, h: 0, i: 1, z: 7
        )
        let scnMatrix = SCNMatrix4(m)
        #expect(abs(Float(scnMatrix.m11) - m.a) < 0.0001)
        #expect(abs(Float(scnMatrix.m21) - m.b) < 0.0001)
        #expect(abs(Float(scnMatrix.m12) - m.d) < 0.0001)
        #expect(abs(Float(scnMatrix.m22) - m.e) < 0.0001)
    }
}
