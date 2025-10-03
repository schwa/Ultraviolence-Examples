// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "UltraviolenceExamples",
    platforms: [
        .iOS("18.5"),
        .macOS("15.5"),
        .visionOS("2.5")
    ],
    products: [
        .library(name: "UltraviolenceExamples", targets: ["UltraviolenceExamples"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/Ultraviolence", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0-latest"),
        .package(url: "https://github.com/schwa/Interaction3D.git", branch: "main"),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.2.0"),
        .package(url: "https://github.com/schwa/GeometryLite3D", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/Panels", branch: "main"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "UltraviolenceExamples",
            dependencies: [
                "UltraviolenceExampleShaders",
                "MikkTSpace",
                .product(name: "Ultraviolence", package: "Ultraviolence"),
                .product(name: "UltraviolenceUI", package: "Ultraviolence"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "Panels", package: "Panels"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [
                .copy("Resources/AppleEventVideo.mp4"),
                .copy("Resources/AppleLogoMask.png"),
                .copy("Resources/DJSI3956.JPG"),
                .copy("Resources/DSC_2595.JPG"),
                .copy("Resources/HD-Testcard-original.jpg"),
                .copy("Resources/IndoorEnvironmentHDRI013_1K-HDR.exr"),
                .copy("Resources/Samples"),
                .copy("Resources/teapot.obj"),
                .copy("Resources/4.2.03.heic"),
            ],
            swiftSettings: [
//                .defaultIsolation(nil)
            ]
        ),
        .testTarget(
            name: "UltraviolenceExamplesTests",
            dependencies: ["UltraviolenceExamples"]
        ),
        .target(
            name: "UltraviolenceExampleShaders",
            publicHeadersPath: ".",
            plugins: [
                .plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")
            ]
        ),
        .target(
            name: "MikkTSpace",
            publicHeadersPath: ".",
        )
    ],
    swiftLanguageModes: [.v6]
)
