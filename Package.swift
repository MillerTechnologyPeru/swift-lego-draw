// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-lego-draw",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "LegoDrawFile", targets: ["LegoDrawFile"]),
        .library(name: "LDrawSceneKit", targets: ["LDrawSceneKit"]),
        .library(name: "LDrawMetal", targets: ["LDrawMetal"]),
        .library(name: "LDrawGLES", targets: ["LDrawGLES"]),
    ],
    targets: [
        .target(
            name: "LegoDrawFile",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LDrawSceneKit",
            dependencies: ["LegoDrawFile"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LDrawMetal",
            dependencies: ["LegoDrawFile"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .systemLibrary(name: "CGLES2"),
        .systemLibrary(name: "CEGL"),
        .target(
            name: "LDrawGLES",
            dependencies: [
                "LegoDrawFile",
                .target(name: "CGLES2", condition: .when(platforms: [.linux])),
                .target(name: "CEGL", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "RenderLDrawModel",
            dependencies: ["LDrawSceneKit"],
            path: "Examples/RenderLDrawModel"
        ),
        .executableTarget(
            name: "MetalLDrawViewer",
            dependencies: ["LDrawMetal"],
            path: "Examples/MetalLDrawViewer"
        ),
        .testTarget(
            name: "LegoDrawFileTests",
            dependencies: ["LegoDrawFile"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "LDrawSceneKitTests",
            dependencies: ["LDrawSceneKit"]
        ),
    ]
)
