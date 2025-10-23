import Metal
import simd
import Ultraviolence
import UltraviolenceSupport

/// Renders a textured quad in 3D world space with YCbCr to RGB conversion
struct TexturedQuad3DPipeline: Element {
    let vertices: [SIMD3<Float>]  // 4 vertices for the quad
    let textureCoords: [SIMD2<Float>]  // 4 texture coordinates
    let textureY: MTLTexture
    let textureCbCr: MTLTexture
    let mvpMatrix: float4x4

    var body: some Element {
        get throws {
            let shaderBundle = Bundle.ultraviolenceExampleShaders().orFatalError("Failed to load ultraviolence example shaders bundle")
            let shaderLibrary = try ShaderLibrary(bundle: shaderBundle, namespace: "TexturedQuad3D")
            let vertexShader: VertexShader = try shaderLibrary.function(named: "vertex_main", type: VertexShader.self)
            let fragmentShader: FragmentShader = try shaderLibrary.function(named: "fragment_main", type: FragmentShader.self)

            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    encoder.setVertexBytes(vertices, length: MemoryLayout<SIMD3<Float>>.stride * vertices.count, index: 0)
                    encoder.setVertexBytes(textureCoords, length: MemoryLayout<SIMD2<Float>>.stride * textureCoords.count, index: 1)
                    var mvp = mvpMatrix
                    encoder.setVertexBytes(&mvp, length: MemoryLayout<float4x4>.stride, index: 2)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
                .parameter("specifierA", value: ColorSource.texture2D(textureY).toArgumentBuffer())
                .parameter("specifierB", value: ColorSource.texture2D(textureCbCr).toArgumentBuffer())
                .useResource(textureY, usage: .read, stages: .fragment)
                .useResource(textureCbCr, usage: .read, stages: .fragment)
            }
            .vertexDescriptor(try vertexShader.inferredVertexDescriptor())
        }
    }
}
