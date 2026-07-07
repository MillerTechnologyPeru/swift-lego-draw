import SceneKit
import LegoDrawFile

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

/// Caches one `SCNMaterial` per distinct ``LDrawResolvedColor``, approximating LDraw
/// surface finishes with SceneKit's physically-based rendering properties.
final class LDrawMaterialCache {

    private var cache: [LDrawResolvedColor: SCNMaterial] = [:]

    func material(for color: LDrawResolvedColor) -> SCNMaterial {
        if let cached = cache[color] {
            return cached
        }

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = platformColor(color)

        switch color.finish {
        case .chrome, .metal:
            material.metalness.contents = 1.0
            material.roughness.contents = 0.05
        case .matteMetallic:
            material.metalness.contents = 0.8
            material.roughness.contents = 0.4
        case .pearlescent:
            material.metalness.contents = 0.3
            material.roughness.contents = 0.2
        case .rubber:
            material.metalness.contents = 0.0
            material.roughness.contents = 0.9
        case .transparent, .solid, .material:
            material.metalness.contents = 0.0
            material.roughness.contents = 0.3
        }

        if color.alpha < 255 {
            material.blendMode = .alpha
            material.isDoubleSided = true
        }

        cache[color] = material
        return material
    }

    private func platformColor(_ color: LDrawResolvedColor) -> PlatformColor {
        PlatformColor(
            red: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: CGFloat(color.alpha) / 255
        )
    }
}
