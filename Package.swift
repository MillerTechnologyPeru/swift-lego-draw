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
        .executableTarget(
            name: "RenderLDrawModel",
            dependencies: ["LDrawSceneKit"],
            path: "Examples/RenderLDrawModel"
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
