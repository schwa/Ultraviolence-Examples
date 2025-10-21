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

public struct EdgeRenderingDemoView: View {
    // Helper struct for edge hashing - uses canonical ordering
    struct Edge: Hashable {
        let startIndex: UInt32
        let endIndex: UInt32

        init(_ a: UInt32, _ b: UInt32) {
            // Canonical ordering: smaller index first
            if a < b {
                startIndex = a
                endIndex = b
            } else {
                startIndex = b
                endIndex = a
            }
        }
    }

    struct MeshWithEdges {
        let mesh: MTKMesh
        let uniqueEdges: [(startIndex: UInt32, endIndex: UInt32)]
    }

    private static func createMesh(type meshType: MeshType) -> MeshWithEdges {
        let device = _MTLCreateSystemDefaultDevice()
        let allocator = MTKMeshBufferAllocator(device: device)

        // Create our standard vertex descriptor: position (float3) + normal (float3) + texCoord (float2) = 32 bytes
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3  // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3  // normal
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float2  // texCoord
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 32

        let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        guard let positionAttr = mdlVertexDescriptor.attributes[0] as? MDLVertexAttribute,
              let normalAttr = mdlVertexDescriptor.attributes[1] as? MDLVertexAttribute,
              let texCoordAttr = mdlVertexDescriptor.attributes[2] as? MDLVertexAttribute else {
            fatalError("Failed to configure vertex descriptor attributes")
        }
        positionAttr.name = MDLVertexAttributePosition
        normalAttr.name = MDLVertexAttributeNormal
        texCoordAttr.name = MDLVertexAttributeTextureCoordinate

        let mdlMesh: MDLMesh
        switch meshType {
        case .plane:
            mdlMesh = MDLMesh(planeWithExtent: [1, 1, 0], segments: [1, 1], geometryType: .triangles, allocator: allocator)
        case .cube:
            mdlMesh = MDLMesh(boxWithExtent: [1, 1, 1], segments: [1, 1, 1], inwardNormals: false, geometryType: .triangles, allocator: allocator)
        case .sphere:
            mdlMesh = MDLMesh(sphereWithExtent: [1, 1, 1], segments: [20, 20], inwardNormals: false, geometryType: .triangles, allocator: allocator)
        case .teapot:
            guard let teapotURL = Bundle.module.url(forResource: "teapot", withExtension: "obj") else {
                fatalError("Failed to find teapot.obj resource")
            }
            let asset = MDLAsset(url: teapotURL, vertexDescriptor: mdlVertexDescriptor, bufferAllocator: allocator)
            guard let mesh = asset.object(at: 0) as? MDLMesh else {
                fatalError("Failed to load teapot mesh from asset")
            }
            mdlMesh = mesh
        }

        mdlMesh.vertexDescriptor = mdlVertexDescriptor

        // Convert all submeshes to use 32-bit indices
        if let submeshes = mdlMesh.submeshes as? [MDLSubmesh] {
            for (index, submesh) in submeshes.enumerated() where submesh.indexType != .uInt32 {
                // Read existing indices
                let indexCount = submesh.indexCount
                let indexBuffer = submesh.indexBuffer
                var indices32 = [UInt32]()
                indices32.reserveCapacity(indexCount)

                if submesh.indexType == .uInt16 {
                    let ptr = indexBuffer.map().bytes.assumingMemoryBound(to: UInt16.self)
                    for i in 0..<indexCount {
                        indices32.append(UInt32(ptr[i]))
                    }
                }

                // Create new 32-bit index buffer
                let newIndexBuffer = allocator.newBuffer(with: Data(bytes: indices32, count: indexCount * MemoryLayout<UInt32>.stride), type: .index)
                let newSubmesh = MDLSubmesh(indexBuffer: newIndexBuffer, indexCount: indexCount, indexType: .uInt32, geometryType: submesh.geometryType, material: submesh.material)
                mdlMesh.submeshes?[index] = newSubmesh
            }
        }

        guard let mtkMesh = try? MTKMesh(mesh: mdlMesh, device: device) else {
            fatalError("Failed to create MTKMesh from MDLMesh")
        }

        // Extract unique edges using a hash set
        var edgeSet = Set<Edge>()
        var uniqueEdges: [(startIndex: UInt32, endIndex: UInt32)] = []

        for submesh in mtkMesh.submeshes {
            let indexBuffer = submesh.indexBuffer.buffer
            let offset = submesh.indexBuffer.offset
            let ptr = indexBuffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt32.self)

            let triangleCount = submesh.indexCount / 3
            for triangleIndex in 0..<triangleCount {
                let i0 = ptr[triangleIndex * 3 + 0]
                let i1 = ptr[triangleIndex * 3 + 1]
                let i2 = ptr[triangleIndex * 3 + 2]

                // Three edges per triangle
                let edges = [
                    Edge(i0, i1),
                    Edge(i1, i2),
                    Edge(i2, i0)
                ]

                for edge in edges where edgeSet.insert(edge).inserted {
                    uniqueEdges.append((edge.startIndex, edge.endIndex))
                }
            }
        }

        return MeshWithEdges(mesh: mtkMesh, uniqueEdges: uniqueEdges)
    }

    @State
    private var lineWidth: Float = 4.0

    @State
    private var rotation: Float = 0

    @State
    private var projection: any ProjectionProtocol = PerspectiveProjection()

    @State
    private var cameraMatrix: simd_float4x4 = .init(translation: [0, 0, -3])

    @State
    private var isAnimating: Bool = true

    @State
    private var meshType: MeshType = .sphere

    @State
    private var colorizeByTriangle: Bool = false

    @State
    private var edgeColor: Color = .white

    @State
    private var scale: Float = 1.0

    @State
    private var debugMode: Bool = false

    @State
    private var cachedMeshWithEdges: MeshWithEdges?

    @State
    private var cachedMeshType: MeshType?

    enum MeshType: String, CaseIterable, Identifiable {
        case plane = "Plane"
        case cube = "Cube"
        case sphere = "Sphere"
        case teapot = "Teapot"

        var id: String { rawValue }
    }

    public init() {
        // Create initial mesh with edges
        _cachedMeshWithEdges = State(initialValue: Self.createMesh(type: .sphere))
        _cachedMeshType = State(initialValue: .sphere)
    }

    public var body: some View {
        WorldView(projection: $projection, cameraMatrix: $cameraMatrix) {
            if isAnimating {
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
        .overlay(alignment: .topLeading) {
            Form {
                LabeledContent("Line Width") {
                    Slider(value: $lineWidth, in: 1...100)
                    Text(lineWidth, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                }

                LabeledContent("Scale") {
                    Slider(value: $scale, in: 0.5...4.0)
                    Text(scale, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                }

                Picker("Mesh", selection: $meshType) {
                    ForEach(MeshType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                Toggle("Animate", isOn: $isAnimating)

                Toggle("Colorize by Triangle", isOn: $colorizeByTriangle)

                if !colorizeByTriangle {
                    ColorPicker("Edge Color", selection: $edgeColor)
                }

                Toggle("Debug Mode (Wireframe)", isOn: $debugMode)
            }
            .frame(width: 300)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
    }

    @ViewBuilder
    private func renderContent(animating: Bool) -> some View {
        let meshWithEdges: MeshWithEdges = {
            if cachedMeshType != meshType {
                let newMesh = Self.createMesh(type: meshType)
                DispatchQueue.main.async {
                    cachedMeshWithEdges = newMesh
                    cachedMeshType = meshType
                }
                return newMesh
            }
            return cachedMeshWithEdges ?? Self.createMesh(type: meshType)
        }()

        RenderView { _, size in
            let scaleMatrix = simd_float4x4(diagonal: [scale, scale, scale, 1])
            let modelMatrix = animating ? scaleMatrix * simd_float4x4(yRotation: .radians(rotation)) : scaleMatrix
            let projectionMatrix = projection.projectionMatrix(for: size)
            let transforms = Transforms(modelMatrix: modelMatrix, cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix)

            let resolved = edgeColor.resolve(in: EnvironmentValues())
            let colorVec = SIMD4<Float>(Float(resolved.red), Float(resolved.green), Float(resolved.blue), Float(resolved.opacity))

            try RenderPass {
                try EdgeRenderingElement(
                    meshWithEdges: meshWithEdges,
                    transforms: transforms,
                    lineWidth: lineWidth,
                    viewport: SIMD2<Float>(Float(size.width), Float(size.height)),
                    colorizeByTriangle: colorizeByTriangle,
                    edgeColor: colorVec,
                    debugMode: debugMode
                )
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .metalDepthStencilPixelFormat(.depth32Float)
    }
}

struct EdgeRenderingElement: Element {
    @UVState
    var edgeDataBuffer: MTLBuffer?

    @UVState
    var meshShader: MeshShader

    @UVState
    var fragmentShader: FragmentShader

    @UVEnvironment(\.device)
    var device

    var meshWithEdges: EdgeRenderingDemoView.MeshWithEdges
    var transforms: Transforms
    var lineWidth: Float
    var viewport: SIMD2<Float>
    var colorizeByTriangle: Bool
    var edgeColor: SIMD4<Float>
    var debugMode: Bool

    init(meshWithEdges: EdgeRenderingDemoView.MeshWithEdges, transforms: Transforms, lineWidth: Float, viewport: SIMD2<Float>, colorizeByTriangle: Bool, edgeColor: SIMD4<Float>, debugMode: Bool) throws {
        self.meshWithEdges = meshWithEdges
        self.transforms = transforms
        self.lineWidth = lineWidth
        self.viewport = viewport
        self.colorizeByTriangle = colorizeByTriangle
        self.edgeColor = edgeColor
        self.debugMode = debugMode

        let library = try ShaderLibrary(bundle: .ultraviolenceExampleShaders(), namespace: "EdgeRendering")
        meshShader = try library.function(named: "edgeRenderingMeshShader", type: MeshShader.self)
        fragmentShader = try library.function(named: "edgeRenderingFragmentShader", type: FragmentShader.self)
    }

    var body: some Element {
        get throws {
            // Create edge data buffer with edge indices
            struct EdgeData {
                var startIndex: UInt32
                var endIndex: UInt32
            }

            if let device {
                let requiredLength = meshWithEdges.uniqueEdges.count * MemoryLayout<EdgeData>.stride
                if edgeDataBuffer == nil || edgeDataBuffer?.length != requiredLength {
                    edgeDataBuffer = device.makeBuffer(length: max(1, requiredLength), options: .storageModeShared)
                    edgeDataBuffer?.label = "Edge Data Buffer"
                }

                if let buffer = edgeDataBuffer {
                    let ptr = buffer.contents().assumingMemoryBound(to: EdgeData.self)
                    for (i, edge) in meshWithEdges.uniqueEdges.enumerated() {
                        ptr[i] = EdgeData(startIndex: edge.startIndex, endIndex: edge.endIndex)
                    }
                }
            }

            let uniforms = EdgeRenderingUniforms(
                viewProjection: transforms.projectionMatrix * transforms.viewMatrix * transforms.modelMatrix,
                viewport: viewport,
                lineWidth: lineWidth,
                colorizeByTriangle: colorizeByTriangle ? 1 : 0,
                edgeColor: edgeColor
            )

            return try Ultraviolence.Group {
                if let vertexBuffer = meshWithEdges.mesh.vertexBuffers.first,
                   let edgeDataBuffer,
                   !meshWithEdges.uniqueEdges.isEmpty {
                    try MeshRenderPipeline(meshShader: meshShader, fragmentShader: fragmentShader) {
                        Draw { encoder in
                            encoder.label = "Edge Rendering"
                            encoder.setCullMode(.none)
                            if debugMode {
                                encoder.setTriangleFillMode(.lines)
                            }
                            encoder.drawMeshThreadgroups(
                                MTLSize(width: meshWithEdges.uniqueEdges.count, height: 1, depth: 1),
                                threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerMeshThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
                            )
                        }
                        .parameter("vertices", functionType: .mesh, buffer: vertexBuffer.buffer, offset: vertexBuffer.offset)
                        .parameter("edgeData", functionType: .mesh, buffer: edgeDataBuffer, offset: 0)
                        .parameter("uniforms", functionType: .mesh, value: uniforms)
                    }
                    .depthCompare(function: .less, enabled: true)
                }
            }
        }
    }
}

// Data structures matching the Metal shader
struct EdgeRenderingUniforms {
    var viewProjection: simd_float4x4
    var viewport: SIMD2<Float>
    var lineWidth: Float
    var colorizeByTriangle: Int32
    var edgeColor: SIMD4<Float>
}
