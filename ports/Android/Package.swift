// swift-tools-version: 6.0
import PackageDescription

// Android build of the headless Vulkan renderer, for on-device testing. Always cross-compiled
// with the Swift Android SDK, e.g.:
//
//   swift build --swift-sdk aarch64-unknown-linux-android28 --product LDrawVulkanAndroid -c release
//
// (driven by ports/Android/Makefile). Produces a *shared library*, not an executable: a plain
// Activity (see AndroidApp/) loads libLDrawVulkanAndroid.so and calls its exported JNI method
// `runVulkanTest` (see Sources/LDrawVulkanAndroid/AndroidMain.swift) directly — there's no SDL
// or on-screen rendering surface involved, since LDrawVulkanOffscreenRenderer renders into an
// off-screen image and reads it back to host memory.
let package = Package(
    name: "LDrawVulkanAndroid",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LDrawVulkanAndroid", type: .dynamic, targets: ["LDrawVulkanAndroid"])
    ],
    dependencies: [
        // Explicit `name:` so the identity stays "swift-lego-draw" even when the repo checkout
        // directory is named something else (e.g. a git worktree).
        .package(name: "swift-lego-draw", path: "../..")
    ],
    targets: [
        // Raw `<jni.h>`/`<android/log.h>` from the NDK sysroot bundled with the Swift Android
        // SDK — no external JNI wrapper package, since the JNI C ABI is stable and small enough
        // to call directly for this one exported test method.
        .systemLibrary(name: "CJNI"),
        .target(
            name: "LDrawVulkanAndroid",
            dependencies: [
                "CJNI",
                .product(name: "LegoDrawFile", package: "swift-lego-draw"),
                .product(name: "LDrawVulkan", package: "swift-lego-draw"),
            ]
        ),
    ]
)
