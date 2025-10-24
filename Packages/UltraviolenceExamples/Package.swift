// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "UltraviolenceExamples",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .visionOS("26.0")
    ],
    products: [
        .library(name: "UltraviolenceExamples", targets: ["UltraviolenceExamples"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/Ultraviolence", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0-latest"),
        .package(url: "https://github.com/schwa/Everything", from: "1.2.0"),
        .package(url: "https://github.com/schwa/Interaction3D", branch: "main"),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", from: "0.1.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/schwa/GeometryLite3D", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/Panels", branch: "main"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0"),
        .package(url: "https://github.com/schwa/earcut-swift", branch: "main"),
        .package(url: "https://github.com/SomeRandomiOSDev/CBORCoding", from: "1.0.0")
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
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "Panels", package: "Panels"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Everything", package: "Everything"),
                .product(name: "earcut", package: "earcut-swift"),
                .product(name: "CBORCoding", package: "CBORCoding"),
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
                .interoperabilityMode(.Cxx)
            ]
        ),
        .testTarget(
            name: "UltraviolenceExamplesTests",
            dependencies: ["UltraviolenceExamples"],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
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
