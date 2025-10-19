import GeometryLite3D
import Interaction3D
import MetalKit
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport
import UltraviolenceUI

public struct GrassDemoView: View {
    @State
    private var projection: any ProjectionProtocol = PerspectiveProjection()

    @State
    private var cameraMatrix: simd_float4x4 = .init(translation: [0, 0, 4])

    @State
    private var rotation: Float = 0.0

    @State
    private var isPlaying: Bool = false

    @State
    private var grassDensity: Double = 500

    private let maxGrassPoints = 2_000

    @State
    private var grassLength: Double = 0.15

    @State
    private var bladeWidthMultiplier: Double = 1.0

    @State
    private var bladesPerPoint: Double = 8

    @State
    private var showSphere: Bool = true

    @State
    private var showGrassLengthSlider: Bool = false

    @State
    private var showBladeWidthSlider: Bool = false

    @State
    private var droopEnabled: Bool = false

    @State
    private var sphereMesh: Mesh

    @State
    private var precomputedGrassPoints: [SIMD3<Float>] = []

    public init() {
        let device = _MTLCreateSystemDefaultDevice()
        let trivialMesh = TrivialMesh.sphere(latitudeSegments: 24, longitudeSegments: 48).scaled([3, 3, 3])
        self.sphereMesh = Mesh(trivialMesh, device: device)
    }

    private func ensurePrecomputedPoints() {
        if precomputedGrassPoints.isEmpty || precomputedGrassPoints.count < maxGrassPoints {
            precomputedGrassPoints = generateUniformSpherePoints(count: maxGrassPoints, radius: 1.5)
        }
    }

    public var body: some View {
        WorldView(projection: $projection, cameraMatrix: $cameraMatrix) {
            Group {
                if isPlaying {
                    TimelineView(.animation) { timeline in
                        renderContent(animating: true)
                            .onChange(of: timeline.date) { _, _ in
                                rotation += 0.01
                            }
                    }
                } else {
                    renderContent(animating: false)
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                let segmentsPerBlade = 4
                let totalBlades = Int(grassDensity) * Int(bladesPerPoint)
                let verticesPerBlade = (segmentsPerBlade + 1) * 2
                let totalVertices = totalBlades * verticesPerBlade

                HStack {
                    Text("Blades: \(totalBlades.formatted())")
                    Text("•")
                    Text("Vertices: \(totalVertices.formatted())")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text("Length")
                            .frame(width: 60, alignment: .leading)
                            .font(.caption)
                        Slider(value: $grassLength, in: 0.05...10.0)
                        Text(String(format: "%.2f", grassLength))
                            .frame(width: 40, alignment: .trailing)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Width")
                            .frame(width: 60, alignment: .leading)
                            .font(.caption)
                        Slider(value: $bladeWidthMultiplier, in: 0.1...3.0)
                        Text(String(format: "%.2f×", bladeWidthMultiplier))
                            .frame(width: 40, alignment: .trailing)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Blades/Pt")
                            .frame(width: 60, alignment: .leading)
                            .font(.caption)
                        Slider(value: $bladesPerPoint, in: 1...16, step: 1)
                        Text(String(format: "%.0f", bladesPerPoint))
                            .frame(width: 40, alignment: .trailing)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Points")
                            .frame(width: 60, alignment: .leading)
                            .font(.caption)
                        Slider(value: $grassDensity, in: 100...Double(maxGrassPoints), step: 100)
                        Text(String(format: "%.0f", grassDensity))
                            .frame(width: 40, alignment: .trailing)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Droop")
                            .frame(width: 60, alignment: .leading)
                            .font(.caption)
                        Toggle("", isOn: $droopEnabled)
                            .labelsHidden()
                        Spacer()
                            .frame(width: 40)
                    }
                }
            }
            .frame(maxWidth: 400)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .toolbar {
            ToolbarItem {
                Button(action: { isPlaying.toggle() }, label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .accessibilityLabel(isPlaying ? "Pause" : "Play")
                })
            }
            ToolbarItem {
                Button(action: { showSphere.toggle() }, label: {
                    Image(systemName: showSphere ? "circle.fill" : "circle")
                        .accessibilityLabel("Toggle sphere")
                })
            }
            ToolbarItem {
                Button(action: {
                    cameraMatrix = .init(translation: [0, 0, 4])
                    rotation = 0.0
                }, label: {
                    Image(systemName: "arrow.counterclockwise")
                        .accessibilityLabel("Reset camera")
                })
            }
        }
    }

    @ViewBuilder
    private func renderContent(animating: Bool) -> some View {
        RenderView { _, drawableSize in
            let projectionMatrix = projection.projectionMatrix(for: drawableSize)
            let viewMatrix = cameraMatrix.inverse
            let rotationMatrix = animating ? float4x4(yRotation: .radians(rotation)) : .identity
            let modelMatrix = rotationMatrix
            let mvp = projectionMatrix * viewMatrix * modelMatrix

            try RenderPass {
                if showSphere {
                    try renderSphere(modelMatrix: modelMatrix, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
                }

                try renderGrass(mvp: mvp, modelMatrix: modelMatrix, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)
            }
        }
        .metalDepthStencilPixelFormat(.depth32Float)
    }

    private func renderSphere(modelMatrix: float4x4, viewMatrix: float4x4, projectionMatrix: float4x4) throws -> some Element {
        try FlatShader(textureSpecifier: .color([0.15, 0.4, 0.2])) {
            try Draw { encoder in
                encoder.setVertexBuffers(of: sphereMesh)
                encoder.draw(mesh: sphereMesh)
            }
            .transforms(.init(modelMatrix: modelMatrix, cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix))
        }
        .vertexDescriptor(sphereMesh.vertexDescriptor)
        .depthCompare(function: .less, enabled: true)
    }

    private func renderGrass(mvp: float4x4, modelMatrix: float4x4, viewMatrix: float4x4, projectionMatrix: float4x4) throws -> some Element {
        ensurePrecomputedPoints()

        let pointCount = Int(grassDensity)
        let grassBladeLength = Float(grassLength)

        let spherePoints = Array(precomputedGrassPoints.prefix(pointCount))

        var grassData: [GrassPointData] = []
        for point in spherePoints {
            let normal = normalize(point)
            let tangent = normalize(cross(normal, [0, 1, 0]))
            let bitangent = normalize(cross(normal, tangent))

            grassData.append(GrassPointData(position: point, normal: normal, tangent: tangent, bitangent: bitangent, bladeLength: grassBladeLength, droopEnabled: droopEnabled ? 1 : 0, bladeWidthMultiplier: Float(bladeWidthMultiplier), bladesPerPoint: Int32(bladesPerPoint)))
        }

        let uniforms = GrassUniforms(modelViewProjection: mvp, modelMatrix: modelMatrix, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix)

        let device = _MTLCreateSystemDefaultDevice()
        let grassDataBuffer = try device.makeBuffer(view: .init(count: grassData.count), values: grassData, options: .storageModeShared)
        let uniformsBuffer = try device.makeBuffer(view: .init(count: 1), values: [uniforms], options: .storageModeShared)

        let shaderBundle = Bundle.ultraviolenceExampleShaders().orFatalError("Failed to load shader bundle")
        let library = try ShaderLibrary(bundle: shaderBundle)
        let objectShader = try library.function(named: "grassObjectShader", type: ObjectShader.self)
        let meshShader = try library.function(named: "grassMeshShader", type: MeshShader.self)
        let fragmentShader = try library.function(named: "grassFragmentShader", type: FragmentShader.self)

        return try MeshRenderPipeline(objectShader: objectShader, meshShader: meshShader, fragmentShader: fragmentShader) {
            Draw { encoder in
                encoder.drawMeshThreadgroups(MTLSize(width: pointCount, height: 1, depth: 1), threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1), threadsPerMeshThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            }
            .parameter("pointData", functionType: .object, buffer: grassDataBuffer, offset: 0)
            .parameter("uniforms", functionType: .object, buffer: uniformsBuffer, offset: 0)
            .parameter("pointData", functionType: .mesh, buffer: grassDataBuffer, offset: 0)
            .parameter("uniforms", functionType: .mesh, buffer: uniformsBuffer, offset: 0)
        }
        .depthCompare(function: .less, enabled: true)
    }

    private func generateUniformSpherePoints(count: Int, radius: Float) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        let goldenRatio = (1.0 + sqrt(5.0)) / 2.0
        let angleIncrement = Float.pi * 2.0 * Float(goldenRatio)

        for i in 0..<count {
            let t = Float(i) / Float(count)
            let inclination = acos(1.0 - 2.0 * t)
            let azimuth = angleIncrement * Float(i)

            let x = sin(inclination) * cos(azimuth)
            let y = sin(inclination) * sin(azimuth)
            let z = cos(inclination)

            points.append(SIMD3<Float>(x, y, z) * radius)
        }

        return points.shuffled()
    }
}

struct GrassPointData {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var tangent: SIMD3<Float>
    var bitangent: SIMD3<Float>
    var bladeLength: Float
    var droopEnabled: Int32
    var bladeWidthMultiplier: Float
    var bladesPerPoint: Int32
}

struct GrassUniforms {
    var modelViewProjection: float4x4
    var modelMatrix: float4x4
    var viewMatrix: float4x4
    var projectionMatrix: float4x4
}
