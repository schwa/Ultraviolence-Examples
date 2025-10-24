import GeometryLite3D
import Interaction3D
import Metal
import MetalKit
import ModelIO
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport
import UltraviolenceUI

public struct PBRDemoView: View {
    @State private var projection: any ProjectionProtocol = PerspectiveProjection()
    @State private var cameraMatrix: simd_float4x4 = .init(translation: [0, 2, 6])
    @State private var selectedMaterial = MaterialPreset.gold
    @State private var customMaterial = PBRMaterialNew()
    @State private var animateLights = true
    @State private var showingInspector = true
    @State private var animationStartTime: Date?
    @State private var animationTime: Double = 0
    @State private var lighting: Lighting

    let teapot: MTKMesh
    let environmentTexture: MTLTexture

    public init() {
        teapot = MTKMesh.teapot(options: [.generateTangentBasis, .generateTextureCoordinatesIfMissing, .useSimpleTextureCoordinates])
        let device = _MTLCreateSystemDefaultDevice()
        let textureLoader = MTKTextureLoader(device: device)
        let envURL = Bundle.module.url(forResource: "IndoorEnvironmentHDRI013_1K-HDR", withExtension: "exr")
            .orFatalError("Missing PBR environment texture")
        environmentTexture = (try? textureLoader.newTexture(URL: envURL, options: [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .generateMipmaps: true,
            .SRGB: false
        ])).orFatalError("Failed to load PBR environment texture")

        lighting = (try? Lighting.demo()).orFatalError("Failed to load demo lighting")
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            WorldView(projection: $projection, cameraMatrix: $cameraMatrix) {
                RenderView { context, drawableSize in
                    let projectionMatrix = projection.projectionMatrix(for: drawableSize)
                    let viewMatrix = cameraMatrix.inverse
                    let viewProjectionMatrix = projectionMatrix * viewMatrix

                    try RenderPass {
                        try AxisLinesRenderPipeline(
                            mvpMatrix: viewProjectionMatrix,
                            viewMatrix: viewMatrix,
                            projectionMatrix: projectionMatrix,
                            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
                        )
                        try AxisAlignedWireframeBoxesRenderPipeline(mvpMatrix: viewProjectionMatrix, boxes: [.init(min: [-10, -10, -10], max: [10, 10, 10], color: [1, 1, 1, 1])])
                        LightingVisualizer(cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix, lighting: lighting)
                        try PBRShader {
                            try Draw(mtkMesh: teapot)
                                .pbrMaterial(currentMaterial)
                                .pbrUniforms(modelTransform: .identity, cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix)
                                .lighting(lighting)
                                .pbrEnvironment(environmentTexture)
                                .parameter("frameUniforms", functionType: .vertex, value: context.frameUniforms)
                                .parameter("frameUniforms", functionType: .fragment, value: context.frameUniforms)
                        }
                        .vertexDescriptor(teapot.vertexDescriptor)
                        .depthCompare(function: .less, enabled: true)
                    }
                }
                .metalDepthStencilPixelFormat(.depth32Float)
                .onChange(of: timeline.date) {
                    // Initialize start time on first frame
                    if animationStartTime == nil {
                        animationStartTime = timeline.date
                    }

                    // Calculate delta time from start
                    if let startTime = animationStartTime {
                        animationTime = timeline.date.timeIntervalSince(startTime)
                    }

                    LightingAnimator.run(date: timeline.date, lighting: &lighting)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // TODO: This technically wont work with the turntable modifier because the turn table has a radius from the rotation point
                VStack {
                    RotationWidget(rotation: $cameraMatrix.rotation)
                        .frame(width: 120, height: 120)
                    Text("(broken)").foregroundStyle(.orange)
                }
                .padding()
                .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                .padding()
        }
        .onChange(of: selectedMaterial, initial: false) {
            if selectedMaterial == .custom {
                customMaterial = PBRMaterialNew()
            }
        }
        .onChange(of: animateLights) {
            // Reset animation start time when toggling animation
            if animateLights {
                animationStartTime = nil
            }
        }
    }

    private var currentMaterial: PBRMaterialNew {
        selectedMaterial == .custom ? customMaterial : selectedMaterial.material
    }
}

extension float4x4 {
    var rotation: simd_quatf {
        get {
            simd_quatf(self)
        }
        set {
            guard var components = decompose else {
                fatalError("Could not decompose transform")
            }
            components.rotation = newValue
            self = .init(components: components)
        }
    }

    init(components: TransformComponents) {
        // Build transformation matrix from components
        // Order: Scale -> Skew -> Rotation -> Translation -> Perspective

        // Start with scale matrix
        var matrix = float4x4(diagonal: [components.scale.x, components.scale.y, components.scale.z, 1])

        // Apply skew
        let skewMatrix = float4x4(
            [1, components.skew.xy, components.skew.xz, 0],
            [0, 1, components.skew.yz, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        )
        matrix = skewMatrix * matrix

        // Apply rotation
        let rotationMatrix = float4x4(components.rotation)
        matrix = rotationMatrix * matrix

        // Apply translation
        matrix.columns.3 = [components.translate.x, components.translate.y, components.translate.z, 1]

        // Apply perspective (if needed)
        // Perspective is typically applied to the last row
        matrix[0][3] = components.perspective.x
        matrix[1][3] = components.perspective.y
        matrix[2][3] = components.perspective.z
        matrix[3][3] = components.perspective.w

        self = matrix
    }
}
