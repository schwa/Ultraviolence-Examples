import Metal
import simd
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport

public struct GraphicsContext3DRenderPipeline: Element {
    let context: GraphicsContext3D
    let viewProjection: float4x4
    let viewport: SIMD2<Float>
    let debugWireframe: Bool

    @UVState
    var objectShader: ObjectShader

    @UVState
    var meshShader: MeshShader

    @UVState
    var meshFragmentShader: FragmentShader

    @UVState
    var fillVertexShader: VertexShader

    @UVState
    var fillFragmentShader: FragmentShader

    @UVState
    var joinDataBuffer: MTLBuffer?

    @UVState
    var uniformsBuffer: MTLBuffer?

    @UVState
    var fillVertexBuffer: MTLBuffer?

    @UVState
    var previousContext: GraphicsContext3D?

    @UVState
    var previousViewProjection: float4x4?

    @UVState
    var previousViewport: SIMD2<Float>?

    @UVState
    var joinCount: Int = 0

    @UVState
    var fillVertexCount: Int = 0

    @UVEnvironment(\.device)
    var device

    public init(context: GraphicsContext3D, viewProjection: float4x4, viewport: SIMD2<Float>, debugWireframe: Bool = false) throws {
        self.context = context
        self.viewProjection = viewProjection
        self.viewport = viewport
        self.debugWireframe = debugWireframe

        let library = try ShaderLibrary(bundle: .ultraviolenceExampleShaders(), namespace: "GraphicsContext3D")
        objectShader = try library.function(named: "lineJoinObjectShader", type: ObjectShader.self)
        meshShader = try library.function(named: "lineJoinMeshShader", type: MeshShader.self)
        meshFragmentShader = try library.function(named: "fragmentShader", type: FragmentShader.self)
        fillVertexShader = try library.function(named: "vertexShader", type: VertexShader.self)
        fillFragmentShader = try library.function(named: "fragmentShader", type: FragmentShader.self)
    }

    public var body: some Element {
        get throws {
            if let device {
                if joinDataBuffer == nil {
                    let bufferSize = 16 * 1_024 * 1_024
                    joinDataBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
                    joinDataBuffer?.label = "GraphicsContext3D Join Data Buffer"
                }

                if uniformsBuffer == nil {
                    uniformsBuffer = device.makeBuffer(length: MemoryLayout<LineJoinUniforms>.stride, options: .storageModeShared)
                    uniformsBuffer?.label = "GraphicsContext3D Uniforms Buffer"
                }

                if fillVertexBuffer == nil {
                    let bufferSize = 64 * 1_024 * 1_024
                    fillVertexBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
                    fillVertexBuffer?.label = "GraphicsContext3D Fill Vertex Buffer"
                }
            }

            let needsRegeneration = previousContext != context || previousViewProjection != viewProjection || previousViewport != viewport

            if needsRegeneration {
                let generator = GeometryGenerator(viewProjection: viewProjection, viewport: viewport)

                var allJoinData: [LineJoinGPUData] = []
                var allFillVertices: [Vertex] = []

                for command in context.commands {
                    switch command {
                    case let .stroke(path, color, style):
                        let joinData = generator.generateLineJoinGPUData(path: path, color: color, style: style)
                        allJoinData.append(contentsOf: joinData)
                    case let .fill(path, color):
                        let vertices = generator.generateFillGeometry(path: path, color: color)
                        allFillVertices.append(contentsOf: vertices)
                    }
                }

                if let buffer = joinDataBuffer, !allJoinData.isEmpty {
                    let byteCount = allJoinData.count * MemoryLayout<LineJoinGPUData>.stride
                    buffer.contents().copyMemory(from: allJoinData, byteCount: byteCount)
                }
                joinCount = allJoinData.count

                if let buffer = fillVertexBuffer, !allFillVertices.isEmpty {
                    let byteCount = allFillVertices.count * MemoryLayout<Vertex>.stride
                    buffer.contents().copyMemory(from: allFillVertices, byteCount: byteCount)
                }
                fillVertexCount = allFillVertices.count

                if let buffer = uniformsBuffer {
                    var uniforms = LineJoinUniforms(
                        viewProjection: viewProjection,
                        viewport: viewport,
                        _padding: (0, 0)
                    )
                    buffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<LineJoinUniforms>.stride)
                }

                previousContext = context
                previousViewProjection = viewProjection
                previousViewport = viewport
            }

            guard let joinDataBuffer, let uniformsBuffer, let fillVertexBuffer else {
                throw UltraviolenceError.resourceCreationFailure("Failed to create required buffers")
            }

            return try Group {
                try MeshRenderPipeline(objectShader: objectShader, meshShader: meshShader, fragmentShader: meshFragmentShader) {
                    Draw { encoder in
                        encoder.withDebugGroup("GraphicsContext3D Stroke Mesh Shader (joinCount: \(joinCount))") {
                            guard joinCount > 0 else {
                                return
                            }
                            encoder.label = "GraphicsContext3D Stroke Mesh Encoder"
                            encoder.setCullMode(.none)
                            encoder.setTriangleFillMode(debugWireframe ? .lines : .fill)
                            encoder.drawMeshThreadgroups(
                                MTLSize(width: joinCount, height: 1, depth: 1),
                                threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerMeshThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
                            )
                        }
                    }
                    .parameter("joinData", functionType: .mesh, buffer: joinDataBuffer, offset: 0)
                    .parameter("uniforms", functionType: .mesh, buffer: uniformsBuffer, offset: 0)
                }
                .depthCompare(function: .less, enabled: true)

                try RenderPipeline(vertexShader: fillVertexShader, fragmentShader: fillFragmentShader) {
                    Draw { encoder in
                        encoder.withDebugGroup("GraphicsContext3D Fill Geometry (fillVertexCount: \(fillVertexCount))") {
                            guard fillVertexCount > 0 else {
                                return
                            }
                            encoder.label = "GraphicsContext3D Fill Encoder"
                            encoder.setCullMode(.none)
                            encoder.setTriangleFillMode(debugWireframe ? .lines : .fill)
                            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: fillVertexCount)
                        }
                    }
                    .parameter("vertices", functionType: .vertex, buffer: fillVertexBuffer, offset: 0)
                }
                .depthCompare(function: .less, enabled: true)
            }
        }
    }
}
