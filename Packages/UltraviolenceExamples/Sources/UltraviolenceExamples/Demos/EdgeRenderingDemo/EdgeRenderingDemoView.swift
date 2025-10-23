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

public struct EdgeLinesDemoView: View {
    private static func createMesh(type meshType: MeshType) -> MeshWithEdges {
        let device = _MTLCreateSystemDefaultDevice()

        // Create TrivialMesh based on mesh type
        let trivialMesh: TrivialMesh
        switch meshType {
        case .plane:
            trivialMesh = TrivialMesh.quad()
        case .cube:
            trivialMesh = TrivialMesh.box()
        case .sphere:
            trivialMesh = TrivialMesh.sphere(latitudeSegments: 20, longitudeSegments: 20)
        case .teapot:
            // For teapot, we still need to load from OBJ file using MDLAsset
            // This is the only case that still requires ModelIO
            let allocator = MTKMeshBufferAllocator(device: device)

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

            guard let teapotURL = Bundle.module.url(forResource: "teapot", withExtension: "obj") else {
                fatalError("Failed to find teapot.obj resource")
            }
            let asset = MDLAsset(url: teapotURL, vertexDescriptor: mdlVertexDescriptor, bufferAllocator: allocator)
            guard let mdlMesh = asset.object(at: 0) as? MDLMesh else {
                fatalError("Failed to load teapot mesh from asset")
            }

            mdlMesh.vertexDescriptor = mdlVertexDescriptor

            // Convert all submeshes to use 32-bit indices
            if let submeshes = mdlMesh.submeshes as? [MDLSubmesh] {
                for (index, submesh) in submeshes.enumerated() where submesh.indexType != .uInt32 {
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

            // Convert MTKMesh to Mesh
            let mesh = Mesh(
                label: "Teapot",
                submeshes: mtkMesh.submeshes.map { submesh in
                    Mesh.Submesh(
                        label: nil,
                        primitiveType: submesh.primitiveType,
                        indices: Mesh.Buffer(
                            buffer: submesh.indexBuffer.buffer,
                            count: submesh.indexCount,
                            offset: submesh.indexBuffer.offset
                        )
                    )
                },
                vertexDescriptor: VertexDescriptor(
                    attributes: [
                        .init(semantic: .position, format: .float3, offset: 0, bufferIndex: 0),
                        .init(semantic: .normal, format: .float3, offset: 12, bufferIndex: 0),
                        .init(semantic: .texcoord, format: .float2, offset: 24, bufferIndex: 0)
                    ],
                    layouts: [
                        .init(bufferIndex: 0, stride: 32, stepFunction: .perVertex, stepRate: 1)
                    ]
                ),
                vertexBuffers: mtkMesh.vertexBuffers.map { buffer in
                    Mesh.Buffer(
                        buffer: buffer.buffer,
                        count: buffer.length / 32,  // stride is 32 bytes
                        offset: buffer.offset
                    )
                }
            )

            return MeshWithEdges(mesh: mesh, uniqueEdges: uniqueEdges)
        }

        // Convert TrivialMesh to Mesh
        let mesh = Mesh(trivialMesh, device: device)

        // Extract unique edges using a hash set
        var edgeSet = Set<Edge>()
        var uniqueEdges: [(startIndex: UInt32, endIndex: UInt32)] = []

        for submesh in mesh.submeshes {
            let indexBuffer = submesh.indices.buffer
            let offset = submesh.indices.offset
            let ptr = indexBuffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt32.self)

            let triangleCount = submesh.indices.count / 3
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

        return MeshWithEdges(mesh: mesh, uniqueEdges: uniqueEdges)
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
                try EdgeLinesRenderPass(
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
        .metalDepthStencilPixelFormat(.depth32Float)
    }
}

