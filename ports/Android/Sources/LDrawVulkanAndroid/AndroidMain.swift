// Android entry point for the headless Vulkan renderer test.
//
// Lifecycle: MainActivity (a plain Activity, see AndroidApp/) extracts the bundled LDraw asset
// files from the APK to internal storage in Java, then calls the exported native method below
// directly (no SDL, no on-screen rendering surface — LDrawVulkanOffscreenRenderer renders into
// an off-screen image and reads it back to host memory, so there's nothing to present).

import Foundation
import CJNI
import LegoDrawFile
import LDrawVulkan

/// The symbol Java's `MainActivity.runVulkanTest` native-method declaration resolves to (JNI
/// name mangling: package dots -> underscores, then `_ClassName_methodName`).
/// Signature: `private native String runVulkanTest(String assetDir, String outputPath, int width, int height);`
@_cdecl("Java_org_ldraw_vulkantest_MainActivity_runVulkanTest")
public func runVulkanTest(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ thiz: jobject,
    _ assetDirJString: jstring?,
    _ outputPathJString: jstring?,
    _ width: jint,
    _ height: jint
) -> jstring? {
    let assetDir = jstringToString(env, assetDirJString) ?? ""
    let outputPath = jstringToString(env, outputPathJString) ?? "/data/local/tmp/ldraw-vulkan-test.ppm"

    let result = runTest(assetDir: assetDir, outputPath: outputPath, width: Int(width), height: Int(height))
    return stringToJString(env, result)
}

// MARK: - Test body

private func runTest(assetDir: String, outputPath: String, width: Int, height: Int) -> String {
    let assetRoot = URL(fileURLWithPath: assetDir, isDirectory: true)

    let colorTable: LDrawColorTable
    if let cfgText = try? String(contentsOf: assetRoot.appendingPathComponent("LDConfig.ldr"), encoding: .utf8),
       let table = try? LDrawColorTable.parsing(ldConfigText: cfgText) {
        colorTable = table
    } else {
        colorTable = LDrawColorTable()
    }
    let defaultColor = colorTable.color(forCode: 4)
        ?? LDrawResolvedColor(name: "Red", code: 4, red: 199, green: 20, blue: 20, edgeRed: 0, edgeGreen: 0, edgeBlue: 0)

    let searchDirs = [
        assetRoot.appendingPathComponent("parts"),
        assetRoot.appendingPathComponent("parts/s"),
        assetRoot.appendingPathComponent("p"),
    ]
    let resolver = AndroidFileSystemPartResolver(searchDirectories: searchDirs)
    let modelResolver = LDrawModelResolver(resolver: resolver, missingPartPolicy: .omit)

    let resolved: ResolvedLDrawModel
    do {
        let text = try String(contentsOf: assetRoot.appendingPathComponent("parts/3001.dat"), encoding: .utf8)
        let parsed = try LDrawParser.parseFile(text)
        resolved = try modelResolver.resolve(parsed)
    } catch {
        return "FAIL: could not load model: \(error)"
    }

    let vertices = LDrawVulkanFlattener(colorTable: colorTable, defaultColor: defaultColor).flatten(resolved)
    guard !vertices.isEmpty else { return "FAIL: model produced no geometry" }

    guard let context = LDrawVulkanContext() else {
        return "FAIL: could not initialize Vulkan (no driver on this device?)"
    }
    guard let renderer = LDrawVulkanOffscreenRenderer(context: context, width: width, height: height) else {
        return "FAIL: could not create Vulkan renderer (missing compiled SPIR-V shaders?)"
    }

    var minP = Vector3(x: vertices[0].px, y: vertices[0].py, z: vertices[0].pz)
    var maxP = minP
    for v in vertices {
        let p = Vector3(x: v.px, y: v.py, z: v.pz)
        minP = Vector3(x: min(minP.x, p.x), y: min(minP.y, p.y), z: min(minP.z, p.z))
        maxP = Vector3(x: max(maxP.x, p.x), y: max(maxP.y, p.y), z: max(maxP.z, p.z))
    }
    let modelRadius = (maxP - minP).length * 0.5
    renderer.modelCenter = (minP + maxP) * 0.5
    renderer.modelRadius = modelRadius
    renderer.distance = modelRadius * 3.5
    renderer.upload(vertices: vertices)

    let pixels = renderer.renderToRGBA()
    guard pixels.count == width * height * 4 else {
        return "FAIL: readback produced \(pixels.count) bytes, expected \(width * height * 4)"
    }

    do {
        try writePPM(rgba: pixels, width: width, height: height, to: outputPath)
    } catch {
        return "FAIL: rendered \(vertices.count / 3) triangles but could not write \(outputPath): \(error)"
    }

    return "OK: rendered \(vertices.count / 3) triangles, \(width)x\(height), wrote \(outputPath)"
}

private func writePPM(rgba: [UInt8], width: Int, height: Int, to path: String) throws {
    var data = Data("P6\n\(width) \(height)\n255\n".utf8)
    var rgb = [UInt8]()
    rgb.reserveCapacity(width * height * 3)
    for i in stride(from: 0, to: rgba.count, by: 4) {
        rgb.append(rgba[i])
        rgb.append(rgba[i + 1])
        rgb.append(rgba[i + 2])
    }
    data.append(contentsOf: rgb)
    try data.write(to: URL(fileURLWithPath: path))
}

// MARK: - Part resolver

private struct AndroidFileSystemPartResolver: LDrawPartResolver {
    var searchDirectories: [URL]

    func resolve(reference: String) throws(LDrawResolutionError) -> LDrawSourceFile? {
        let normalized = reference.replacingOccurrences(of: "\\", with: "/")
        for dir in searchDirectories {
            for name in [normalized, normalized.lowercased()] {
                let url = dir.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                guard let file = try? LDrawParser.parseFile(text) else { continue }
                return file
            }
        }
        return nil
    }
}

// MARK: - JNI string helpers

private func jstringToString(_ env: UnsafeMutablePointer<JNIEnv?>, _ value: jstring?) -> String? {
    guard let value else { return nil }
    guard let cStr = env.pointee?.pointee.GetStringUTFChars(env, value, nil) else { return nil }
    defer { env.pointee?.pointee.ReleaseStringUTFChars(env, value, cStr) }
    return String(cString: cStr)
}

private func stringToJString(_ env: UnsafeMutablePointer<JNIEnv?>, _ value: String) -> jstring? {
    value.withCString { cStr in
        env.pointee?.pointee.NewStringUTF(env, cStr)
    }
}
