import Metal
import simd
import Ultraviolence
import UltraviolenceExampleShaders

public struct AxisLinesRenderPipeline: Element {
    let vertexShader: VertexShader
    let fragmentShader: FragmentShader
    let mvpMatrix: float4x4
    let viewMatrix: float4x4
    let projectionMatrix: float4x4
    let viewportSize: SIMD2<Float>
    let lineWidth: Float
    let nudge: SIMD3<Float>
    let xAxisColor: SIMD4<Float>
    let yAxisColor: SIMD4<Float>
    let zAxisColor: SIMD4<Float>

    public init(
        mvpMatrix: float4x4,
        viewMatrix: float4x4,
        projectionMatrix: float4x4,
        viewportSize: SIMD2<Float>,
        lineWidth: Float = 2.0,
        nudge: SIMD3<Float> = .zero,
        xAxisColor: SIMD4<Float> = [1, 0, 0, 1],
        yAxisColor: SIMD4<Float> = [0, 1, 0, 1],
        zAxisColor: SIMD4<Float> = [0, 0, 1, 1]
    ) throws {
        let library = try ShaderLibrary(bundle: .ultraviolenceExampleShaders(), namespace: "AxisLines")
        vertexShader = try library.vertex_main
        fragmentShader = try library.fragment_main
        self.mvpMatrix = mvpMatrix
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.viewportSize = viewportSize
        self.lineWidth = lineWidth
        self.nudge = nudge
        self.xAxisColor = xAxisColor
        self.yAxisColor = yAxisColor
        self.zAxisColor = zAxisColor
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    let uniforms = AxisLinesUniforms(
                        mvpMatrix: mvpMatrix,
                        viewMatrix: viewMatrix,
                        projectionMatrix: projectionMatrix,
                        viewportSize: viewportSize,
                        lineWidth: lineWidth,
                        nudge: nudge,
                        xAxisColor: xAxisColor,
                        yAxisColor: yAxisColor,
                        zAxisColor: zAxisColor
                    )
                    encoder.setVertexBytes([uniforms], length: MemoryLayout<AxisLinesUniforms>.size, index: 0)
                    // Draw 3 axes, each with 6 vertices (2 triangles per quad)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 18)
                }
            }
            .vertexDescriptor(try vertexShader.inferredVertexDescriptor())
        }
    }
}
