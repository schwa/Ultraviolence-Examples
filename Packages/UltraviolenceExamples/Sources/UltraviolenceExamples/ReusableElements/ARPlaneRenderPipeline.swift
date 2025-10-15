#if os(iOS)
import ARKit
import Metal
import MetalKit
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport

struct ARPlaneRenderPipeline: Element {
    let vertexShader: VertexShader
    let fragmentShader: FragmentShader
    var mvpMatrix: float4x4
    var color: SIMD4<Float>
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int

    init(mvpMatrix: float4x4, planeAnchor: ARPlaneAnchor, color: SIMD4<Float>) throws {
        let shaderBundle = Bundle.ultraviolenceExampleShaders().orFatalError("Failed to load ultraviolence example shaders bundle")
        let shaderLibrary = try ShaderLibrary(bundle: shaderBundle, namespace: "WireframeShader")
        self.vertexShader = try shaderLibrary.vertex_main
        self.fragmentShader = try shaderLibrary.fragment_main
        self.mvpMatrix = mvpMatrix
        self.color = color

        let device = _MTLCreateSystemDefaultDevice()

        // Create simple rectangle from plane extent (width and height)
        let halfWidth = planeAnchor.planeExtent.width / 2
        let halfHeight = planeAnchor.planeExtent.height / 2
        let rectVertices: [SIMD3<Float>] = [
            [-halfWidth, 0, -halfHeight],  // bottom-left
            [halfWidth, 0, -halfHeight],   // bottom-right
            [halfWidth, 0, halfHeight],    // top-right
            [-halfWidth, 0, halfHeight]    // top-left
        ]

        self.vertexBuffer = device.makeBuffer(bytes: rectVertices, length: MemoryLayout<SIMD3<Float>>.stride * rectVertices.count, options: []).orFatalError("Failed to create vertex buffer")
        self.vertexBuffer.label = "Plane Rectangle Vertices"

        // Indices for rectangle outline (line loop)
        let rectIndices: [UInt16] = [0, 1, 1, 2, 2, 3, 3, 0]
        self.indexBuffer = device.makeBuffer(bytes: rectIndices, length: MemoryLayout<UInt16>.stride * rectIndices.count, options: []).orFatalError("Failed to create index buffer")
        self.indexBuffer.label = "Plane Rectangle Indices"
        self.indexCount = rectIndices.count

        // COMMENTED OUT: Triangle rendering code for later
        // let planeGeometry = planeAnchor.geometry
        // let vertexData = planeGeometry.vertices
        // self.vertexBuffer = device.makeBuffer(bytes: vertexData, length: MemoryLayout<SIMD3<Float>>.stride * vertexData.count, options: []).orFatalError("Failed to create vertex buffer")
        // self.vertexBuffer.label = "Plane Vertices"
        //
        // let indexData = planeGeometry.triangleIndices
        // self.indexBuffer = device.makeBuffer(bytes: indexData, length: MemoryLayout<Int16>.stride * indexData.count, options: []).orFatalError("Failed to create index buffer")
        // self.indexBuffer.label = "Plane Indices"
        // self.indexCount = indexData.count
    }

    var body: some Element {
        get throws {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                let uniforms = WireframeUniforms(modelViewProjectionMatrix: mvpMatrix, wireframeColor: color)
                Draw { encoder in
                    encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                    encoder.drawIndexedPrimitives(type: .line, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
                }
                .parameter("uniforms", functionType: .vertex, value: uniforms)
                .parameter("uniforms", functionType: .fragment, value: uniforms)
            }
            .vertexDescriptor(try vertexShader.inferredVertexDescriptor())
        }
    }
}
#endif
