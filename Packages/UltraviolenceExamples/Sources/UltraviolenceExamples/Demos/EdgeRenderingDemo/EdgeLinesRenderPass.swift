import GeometryLite3D
import Interaction3D
import Metal
import MetalKit
import ModelIO
import simd
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport

// struct EdgeRenderingUniforms {
//    var viewProjection: simd_float4x4
//    var viewport: SIMD2<Float>
//    var lineWidth: Float
//    var colorizeByTriangle: Int32
//    var edgeColor: SIMD4<Float>
// }

struct EdgeLinesRenderPass: Element {
    @UVState
    var edgeDataBuffer: MTLBuffer?

    @UVState
    var meshShader: MeshShader

    @UVState
    var fragmentShader: FragmentShader

    @UVEnvironment(\.device)
    var device

    var meshWithEdges: MeshWithEdges
    var transforms: Transforms
    var lineWidth: Float
    var viewport: SIMD2<Float>
    var colorizeByTriangle: Bool
    var edgeColor: SIMD4<Float>
    var debugMode: Bool

    init(meshWithEdges: MeshWithEdges, transforms: Transforms, lineWidth: Float, viewport: SIMD2<Float>, colorizeByTriangle: Bool, edgeColor: SIMD4<Float>, debugMode: Bool) throws {
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

            // Create BufferDescriptor for vertex buffer
            let descriptor = meshWithEdges.mesh.vertexDescriptor
            guard let positionAttr = descriptor.attributes.first(where: { $0.semantic == .position }) else {
                fatalError("EdgeLinesRenderPass: Mesh vertex descriptor must have a position attribute")
            }
            guard let layout = descriptor.layouts[positionAttr.bufferIndex] else {
                fatalError("EdgeLinesRenderPass: Mesh vertex descriptor must have a layout for buffer \(positionAttr.bufferIndex)")
            }
            guard let vertexBuffer = meshWithEdges.mesh.vertexBuffers.first else {
                fatalError("EdgeLinesRenderPass: Mesh must have at least one vertex buffer")
            }

            // Calculate vertex count from buffer size / stride
            let vertexCount = vertexBuffer.buffer.length / layout.stride

            let bufferDescriptor = BufferDescriptor(
                count: UInt32(vertexCount),
                stride: UInt32(layout.stride),
                valueOffset: UInt32(positionAttr.offset)
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
                        .parameter("vertexDescriptor", functionType: .mesh, value: bufferDescriptor)
                        .parameter("uniforms", functionType: .mesh, value: uniforms)
                    }
                    .depthCompare(function: .less, enabled: true)
                }
            }
        }
    }
}
