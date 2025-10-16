import Metal
import simd
import Ultraviolence

public struct GraphicsContext3DRenderPipeline: Element {
    let context: GraphicsContext3D
    let viewProjection: float4x4
    let viewport: SIMD2<Float>
    let debugWireframe: Bool

    @UVState
    var vertexShader: VertexShader

    @UVState
    var fragmentShader: FragmentShader

    @UVState
    var vertexBuffer: MTLBuffer?

    @UVState
    var previousContext: GraphicsContext3D?

    @UVState
    var previousViewProjection: float4x4?

    @UVState
    var previousViewport: SIMD2<Float>?

    @UVState
    var vertexCount: Int = 0

    @UVEnvironment(\.device)
    var device

    public init(context: GraphicsContext3D, viewProjection: float4x4, viewport: SIMD2<Float>, debugWireframe: Bool = false) throws {
        self.context = context
        self.viewProjection = viewProjection
        self.viewport = viewport
        self.debugWireframe = debugWireframe

        let library = try ShaderLibrary(bundle: .ultraviolenceExampleShaders())
        vertexShader = try library.function(named: "graphicsContext3D_vertex", type: VertexShader.self)
        fragmentShader = try library.function(named: "graphicsContext3D_fragment", type: FragmentShader.self)
    }

    public var body: some Element {
        get throws {
            if let device, vertexBuffer == nil {
                let bufferSize = 64 * 1024 * 1024
                vertexBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
                vertexBuffer?.label = "GraphicsContext3D Vertex Buffer"
            }

            let needsRegeneration = previousContext != context || previousViewProjection != viewProjection || previousViewport != viewport

            if needsRegeneration {
                let generator = GeometryGenerator(viewProjection: viewProjection, viewport: viewport)
                var allVertices: [Vertex] = []

                for command in context.commands {
                    switch command {
                    case .stroke(let path, let color, let style):
                        let vertices = generator.generateStrokeGeometry(path: path, color: color, style: style)
                        allVertices.append(contentsOf: vertices)
                    case .fill(let path, let color):
                        let vertices = generator.generateFillGeometry(path: path, color: color)
                        allVertices.append(contentsOf: vertices)
                    }
                }

                let byteCount = allVertices.count * MemoryLayout<Vertex>.stride
                print("Regenerating vertex buffer: \(byteCount) bytes (\(allVertices.count) vertices)")

                if let buffer = vertexBuffer {
                    buffer.contents().copyMemory(from: allVertices, byteCount: byteCount)
                }

                vertexCount = allVertices.count
                previousContext = context
                previousViewProjection = viewProjection
                previousViewport = viewport
            }

            return try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    guard vertexCount > 0, let buffer = vertexBuffer else {
                        return
                    }
                    encoder.setCullMode(.none)
                    encoder.setTriangleFillMode(debugWireframe ? .lines : .fill)
                    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
                }
            }
            .depthCompare(function: .less, enabled: true)
        }
    }
}
