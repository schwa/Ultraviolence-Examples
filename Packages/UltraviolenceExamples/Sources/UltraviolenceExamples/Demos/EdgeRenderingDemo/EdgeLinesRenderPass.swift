import GeometryLite3D
import Interaction3D
import Metal
import MetalKit
import ModelIO
import simd
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport

//struct EdgeRenderingUniforms {
//    var viewProjection: simd_float4x4
//    var viewport: SIMD2<Float>
//    var lineWidth: Float
//    var colorizeByTriangle: Int32
//    var edgeColor: SIMD4<Float>
//}

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
        // Validate vertex descriptor compatibility
        // The shader expects: struct Vertex { packed_float3 position; packed_float3 normal; float2 texCoord; }
        // Total size: 12 + 12 + 8 = 32 bytes
        // At minimum, we need a position attribute with format .float3 at offset 0 in buffer 0
        let descriptor = meshWithEdges.mesh.vertexDescriptor
        guard let positionAttr = descriptor.attributes.first(where: { $0.semantic == .position }) else {
            fatalError("EdgeLinesRenderPass: Mesh vertex descriptor must have a position attribute")
        }
        guard positionAttr.format == .float3 else {
            fatalError("EdgeLinesRenderPass: Position attribute must have format .float3, got \(positionAttr.format)")
        }
        guard positionAttr.offset == 0 else {
            fatalError("EdgeLinesRenderPass: Position attribute must be at offset 0, got \(positionAttr.offset)")
        }
        guard positionAttr.bufferIndex == 0 else {
            fatalError("EdgeLinesRenderPass: Position attribute must use buffer index 0, got \(positionAttr.bufferIndex)")
        }

        // Validate stride - shader expects 32 bytes (packed_float3 + packed_float3 + float2)
        guard let layout = descriptor.layouts[0] else {
            fatalError("EdgeLinesRenderPass: Mesh vertex descriptor must have a layout for buffer 0")
        }
        guard layout.stride == 32 else {
            fatalError("EdgeLinesRenderPass: Vertex stride must be 32 bytes (packed_float3 position + packed_float3 normal + float2 texCoord), got \(layout.stride)")
        }

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
