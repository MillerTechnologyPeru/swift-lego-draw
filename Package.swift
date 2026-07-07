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
        .library(name: "LDrawSDL", targets: ["LDrawSDL"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PureSwift/SDL.git", from: "3.1.0"),
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
            name: "LDrawSDL",
            dependencies: [
                "LegoDrawFile",
                .product(name: "SDL3Swift", package: "SDL"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "RenderLDrawModel",
            dependencies: ["LDrawSceneKit"],
            path: "Examples/RenderLDrawModel"
        ),
        .executableTarget(
            name: "SDLLDrawViewer",
            dependencies: ["LDrawSDL"],
            path: "Examples/SDLLDrawViewer"
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
