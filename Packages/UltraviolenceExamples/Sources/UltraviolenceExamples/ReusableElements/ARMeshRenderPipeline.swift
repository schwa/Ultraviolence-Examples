#if os(iOS)
import ARKit
import Metal
import Ultraviolence
import UltraviolenceExampleShaders

struct ARMeshRenderPipeline: Element {
    let vertexShader: VertexShader
    let fragmentShader: FragmentShader
    var mvpMatrix: float4x4
    var color: SIMD4<Float>
    var meshGeometry: ARMeshGeometry

    init(mvpMatrix: float4x4, meshGeometry: ARMeshGeometry, color: SIMD4<Float>) throws {
        let shaderBundle = Bundle.ultraviolenceExampleShaders().orFatalError("Failed to load ultraviolence example shaders bundle")
        let shaderLibrary = try ShaderLibrary(bundle: shaderBundle, namespace: "WireframeShader")
        self.vertexShader = try shaderLibrary.vertex_main
        self.fragmentShader = try shaderLibrary.fragment_main
        self.mvpMatrix = mvpMatrix
        self.color = color
        self.meshGeometry = meshGeometry
    }

    var body: some Element {
        get throws {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                let uniforms = WireframeUniforms(modelViewProjectionMatrix: mvpMatrix, wireframeColor: color)
                Draw { encoder in
                    encoder.setTriangleFillMode(.lines)
                    encoder.setVertexBuffer(meshGeometry.vertices.buffer, offset: meshGeometry.vertices.offset, index: 0)
                    encoder.drawIndexedPrimitives(type: .triangle, indexCount: meshGeometry.faces.count * meshGeometry.faces.indexCountPerPrimitive, indexType: meshGeometry.faces.bytesPerIndex == 2 ? .uint16 : .uint32, indexBuffer: meshGeometry.faces.buffer, indexBufferOffset: 0)
                }
                .parameter("uniforms", functionType: .vertex, value: uniforms)
                .parameter("uniforms", functionType: .fragment, value: uniforms)
            }
            .vertexDescriptor(try vertexShader.inferredVertexDescriptor())
        }
    }
}
#endif
