// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UltraviolenceExamples",
    platforms: [
        .iOS("18.2"),
        .macOS("15.2")
    ],
    products: [
        .library(name: "UltraviolenceExamples", targets: ["UltraviolenceExamples"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/Ultraviolence", branch: "main"),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", branch: "jwight/develop"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "UltraviolenceExamples",
            dependencies: [
                "Ultraviolence",
                "UltraviolenceExampleShaders",
                .product(name: "UltraviolenceUI", package: "Ultraviolence"),
                "GaussianSplatShaders",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ]
        ),
        .target(
            name: "UltraviolenceExampleShaders",
            exclude: [
                "BlinnPhongShaders.metal",
                "FlatShader.metal"
            ],
            plugins: [
                .plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")
            ]
        ),


        .executableTarget(
            name: "UltraviolenceCLI",
            dependencies: [
                "Ultraviolence",
                .product(name: "UltraviolenceSupport", package: "Ultraviolence"),
                "UltraviolenceExamples",
            ],
            resources: [
                .copy("Teapot.usdz")
            ],
        ),



        .target(
            name: "GaussianSplatShaders",
            exclude: [
            ],
            plugins: [
                .plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")
            ]
        ),

        .testTarget(
            name: "UltraviolenceExamplesTests",
            dependencies: ["UltraviolenceExamples"]
        )
    ],
    swiftLanguageModes: [.v6]
)
