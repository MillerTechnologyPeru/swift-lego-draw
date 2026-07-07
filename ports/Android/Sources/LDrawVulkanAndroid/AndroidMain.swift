// Android entry point for the on-screen, spinning Vulkan demo.
//
// Lifecycle: MainActivity (a SurfaceView-backed Activity, see AndroidApp/) extracts the bundled
// LDraw asset files + compiled shaders from the APK to internal storage in Java, then forwards
// its SurfaceHolder callbacks (surfaceCreated/surfaceDestroyed) to the native methods below.
// `nativeSurfaceCreated` wraps the Java `Surface` in an `ANativeWindow`, creates a Vulkan
// instance/device/swapchain against it, and starts a background render loop that spins the
// model — the Vulkan equivalent of the OpenGL ES playground's `CADisplayLink`-driven auto-rotate.

import Foundation
import CJNI
import CVulkan
import LegoDrawFile
import LDrawVulkan

private let logger = AndroidLog(tag: "LDrawVulkanTest")

// MARK: - JNI entry points

/// Signature: `private native void nativeSurfaceCreated(Surface surface, String assetDir, String shaderDir, int width, int height);`
@_cdecl("Java_org_ldraw_vulkantest_MainActivity_nativeSurfaceCreated")
public func nativeSurfaceCreated(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ thiz: jobject,
    _ surface: jobject?,
    _ assetDirJString: jstring?,
    _ shaderDirJString: jstring?,
    _ width: jint,
    _ height: jint
) {
    guard let surface, let nativeWindow = ANativeWindow_fromSurface(env, surface) else {
        logger.error("nativeSurfaceCreated: no ANativeWindow")
        return
    }
    let assetDir = jstringToString(env, assetDirJString) ?? ""
    let shaderDir = jstringToString(env, shaderDirJString) ?? ""
    RenderSession.start(nativeWindow: nativeWindow, assetDir: assetDir, shaderDir: shaderDir, width: Int(width), height: Int(height))
}

/// Signature: `private native void nativeSurfaceDestroyed();`
@_cdecl("Java_org_ldraw_vulkantest_MainActivity_nativeSurfaceDestroyed")
public func nativeSurfaceDestroyed(_ env: UnsafeMutablePointer<JNIEnv?>, _ thiz: jobject) {
    RenderSession.stop()
}

// MARK: - Render session

/// Owns the Vulkan instance/device/swapchain for the lifetime of the Activity's `Surface`, and
/// drives a background thread that spins the model and presents a frame every ~16ms. One session
/// at a time — `start` tears down any previous session first (handles the emulator/device
/// occasionally re-creating the surface without an intervening destroy).
private final class RenderSession: @unchecked Sendable {
    // Only ever touched from the JVM thread that calls the JNI entry points below (Java's
    // SurfaceHolder callbacks are always delivered serially on the same thread), so a plain
    // global is safe despite not being provably so to the compiler.
    nonisolated(unsafe) static var current: RenderSession?

    private let nativeWindow: OpaquePointer
    // var + explicitly niled (not left to ARC) so requestStop() can force teardown order:
    // renderer must destroy its swapchain before we destroy the VkSurfaceKHR it was built from,
    // and the context (device/instance) must outlive both.
    private var context: LDrawVulkanContext!
    private var renderer: LDrawVulkanSwapchainRenderer!
    private let surface: VkSurfaceKHR
    private var thread: Thread?
    private let stateLock = NSLock()
    private var shouldStop = false

    static func start(nativeWindow: OpaquePointer, assetDir: String, shaderDir: String, width: Int, height: Int) {
        stop()
        guard let session = RenderSession(nativeWindow: nativeWindow, assetDir: assetDir, shaderDir: shaderDir, width: width, height: height) else {
            logger.error("RenderSession: setup failed")
            ANativeWindow_release(nativeWindow)
            return
        }
        current = session
        session.startLoop()
    }

    static func stop() {
        current?.requestStop()
        current = nil
    }

    private init?(nativeWindow: OpaquePointer, assetDir: String, shaderDir: String, width: Int, height: Int) {
        self.nativeWindow = nativeWindow

        guard let context = LDrawVulkanContext(
            instanceExtensions: ["VK_KHR_surface", "VK_KHR_android_surface"],
            deviceExtensions: ["VK_KHR_swapchain"]
        ) else {
            logger.error("Vulkan instance/device creation failed")
            return nil
        }
        self.context = context

        var surfaceCreateInfo = VkAndroidSurfaceCreateInfoKHR()
        surfaceCreateInfo.sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR
        surfaceCreateInfo.window = nativeWindow
        var createdSurface: VkSurfaceKHR? = nil
        guard vkCreateAndroidSurfaceKHR(context.instance, &surfaceCreateInfo, nil, &createdSurface) == VK_SUCCESS,
              let createdSurface
        else {
            logger.error("vkCreateAndroidSurfaceKHR failed")
            return nil
        }
        self.surface = createdSurface

        guard let renderer = LDrawVulkanSwapchainRenderer(
            context: context, surface: createdSurface, width: width, height: height,
            shaderDirectory: URL(fileURLWithPath: shaderDir, isDirectory: true)
        ) else {
            logger.error("LDrawVulkanSwapchainRenderer creation failed (missing compiled .spv shaders?)")
            return nil
        }
        self.renderer = renderer

        loadModel(assetDir: assetDir, into: renderer)
    }

    private func startLoop() {
        let t = Thread { [self] in
            while true {
                stateLock.lock()
                let stop = shouldStop
                stateLock.unlock()
                if stop { break }

                renderer.azimuth += 0.01
                renderer.drawFrame()
                Thread.sleep(forTimeInterval: 1.0 / 60.0)
            }
        }
        t.name = "LDrawVulkanRenderLoop"
        thread = t
        t.start()
    }

    private func requestStop() {
        stateLock.lock()
        shouldStop = true
        stateLock.unlock()
        // Give the loop a moment to exit its current drawFrame() before we tear down Vulkan
        // objects out from under it.
        while thread?.isExecuting == true {
            Thread.sleep(forTimeInterval: 0.005)
        }
        // Order matters: the renderer's deinit calls vkDeviceWaitIdle and destroys the swapchain
        // built from `surface` — that must happen *before* we destroy the surface itself, or the
        // driver is left with a dangling swapchain->surface reference (this previously wedged
        // the emulator's Vulkan driver entirely, taking the whole device offline).
        renderer = nil
        vkDestroySurfaceKHR(context.instance, surface, nil)
        ANativeWindow_release(nativeWindow)
        context = nil
    }
}

// MARK: - Model loading

private func loadModel(assetDir: String, into renderer: LDrawVulkanSwapchainRenderer) {
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

    guard
        let text = try? String(contentsOf: assetRoot.appendingPathComponent("parts/3001.dat"), encoding: .utf8),
        let parsed = try? LDrawParser.parseFile(text),
        let resolved = try? modelResolver.resolve(parsed)
    else {
        logger.error("Failed to load bundled model")
        return
    }

    let vertices = LDrawVulkanFlattener(colorTable: colorTable, defaultColor: defaultColor).flatten(resolved)
    guard !vertices.isEmpty else {
        logger.error("Model produced no geometry")
        return
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

    logger.info("Loaded model: \(vertices.count / 3) triangles")
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

// MARK: - logcat

private struct AndroidLog {
    let tag: String
    func info(_ message: String) { log(ANDROID_LOG_INFO, message) }
    func error(_ message: String) { log(ANDROID_LOG_ERROR, message) }
    private func log(_ priority: android_LogPriority, _ message: String) {
        _ = __android_log_write(Int32(priority.rawValue), tag, message)
    }
}
