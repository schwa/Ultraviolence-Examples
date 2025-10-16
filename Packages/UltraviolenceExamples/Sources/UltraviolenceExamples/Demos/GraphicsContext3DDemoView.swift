import GeometryLite3D
import Interaction3D
import MetalKit
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceSupport
import UltraviolenceUI

public struct GraphicsContext3DDemoView: View {
    enum Sample: String, CaseIterable, Identifiable {
        case lineCaps = "Line Caps"
        case lineJoins = "Line Joins"
        case miter = "Miter"
        case curves = "Curves"
        case geometry = "Geometry"
        case randomLines = "Random Lines"

        var id: String { rawValue }
    }

    @State
    private var selectedSample: Sample = .lineCaps

    @State
    private var rotation: Float = 0.0

    @State
    private var projection: any ProjectionProtocol = PerspectiveProjection()

    @State
    private var cameraMatrix: simd_float4x4 = .init(translation: [0, 0, 8])

    @State
    private var isPlaying: Bool = false

    @State
    private var debugWireframe: Bool = false

    @State
    private var lineWidthMultiplier: Double = 1.0

    @State
    private var showLineWidthPopover: Bool = false

    @State
    private var randomLineCount: Int = 1000

    @State
    private var showRandomLineCountPopover: Bool = false

    @State
    private var randomLines: [(start: SIMD3<Float>, end: SIMD3<Float>, color: Color)] = []

    public init() {
        // Empty initializer
    }

    public var body: some View {
        WorldView(projection: $projection, cameraMatrix: $cameraMatrix) {
            TimelineView(.animation) { timeline in
                RenderView { _, drawableSize in
                    let projectionMatrix = projection.projectionMatrix(for: drawableSize)
                    let viewMatrix = cameraMatrix.inverse
                    let rotationMatrix = float4x4(yRotation: .radians(rotation))
                    let viewProjection = projectionMatrix * viewMatrix * rotationMatrix

                    try RenderPass {
                        try GraphicsContext3DRenderPipeline(context: currentContext, viewProjection: viewProjection, viewport: [Float(drawableSize.width), Float(drawableSize.height)], debugWireframe: debugWireframe)
                    }
                }
                .metalDepthStencilPixelFormat(.depth32Float)
                .onChange(of: timeline.date) {
                    if isPlaying {
                        rotation += 0.01
                    }
                }
            }
        }
        .toolbar {
            toolbarContent
        }
        .onAppear {
            generateRandomLines()
        }
        .onChange(of: randomLineCount) {
            generateRandomLines()
        }
    }

    private func generateRandomLines() {
        let cubeSize: Float = 4.0
        randomLines = (0..<randomLineCount).map { _ in
            let start = SIMD3<Float>(Float.random(in: -cubeSize...cubeSize), Float.random(in: -cubeSize...cubeSize), Float.random(in: -cubeSize...cubeSize))
            let end = SIMD3<Float>(Float.random(in: -cubeSize...cubeSize), Float.random(in: -cubeSize...cubeSize), Float.random(in: -cubeSize...cubeSize))
            let color = Color(red: Double.random(in: 0...1), green: Double.random(in: 0...1), blue: Double.random(in: 0...1))
            return (start, end, color)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("Sample", selection: $selectedSample) {
                ForEach(Sample.allCases) { sample in
                    Text(sample.rawValue).tag(sample)
                }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItem {
            Button(action: { isPlaying.toggle() }, label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            })
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
        ToolbarItem {
            Button(action: { debugWireframe.toggle() }, label: {
                Image(systemName: debugWireframe ? "grid.circle.fill" : "grid.circle")
            })
            .accessibilityLabel("Toggle Debug Wireframe")
        }
        ToolbarItem {
            Button(action: {
                cameraMatrix = .init(translation: [0, 0, 8])
                rotation = 0.0
            }, label: {
                Image(systemName: "arrow.counterclockwise")
            })
            .accessibilityLabel("Reset Camera")
        }
        ToolbarItem {
            Button(action: { showLineWidthPopover.toggle() }, label: {
                Image(systemName: "lineweight")
            })
            .accessibilityLabel("Line Width Settings")
            .popover(isPresented: $showLineWidthPopover) {
                VStack {
                    Text("Line Width Multiplier")
                        .font(.headline)
                    Slider(value: $lineWidthMultiplier, in: 0.1...20.0)
                    Text(String(format: "%.2f", lineWidthMultiplier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(minWidth: 200)
            }
        }
        ToolbarItem {
            Button(action: { showRandomLineCountPopover.toggle() }, label: {
                Image(systemName: "number")
            })
            .accessibilityLabel("Random Line Count")
            .popover(isPresented: $showRandomLineCountPopover) {
                VStack {
                    Text("Random Line Count")
                        .font(.headline)
                    Slider(value: Binding(get: { Double(randomLineCount) }, set: { randomLineCount = Int($0) }), in: 10...20000, step: 10)
                    Text("\(randomLineCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(minWidth: 200)
            }
        }
    }

    private var currentContext: GraphicsContext3D {
        selectedSample.buildContext(lineWidthMultiplier: lineWidthMultiplier, randomLines: randomLines)
    }
}

extension GraphicsContext3DDemoView.Sample {
    func buildContext(lineWidthMultiplier: Double, randomLines: [(start: SIMD3<Float>, end: SIMD3<Float>, color: Color)]) -> GraphicsContext3D {
        switch self {
        case .lineCaps:
            return buildLineCapsContext(lineWidthMultiplier: lineWidthMultiplier)
        case .lineJoins:
            return buildLineJoinsContext(lineWidthMultiplier: lineWidthMultiplier)
        case .miter:
            return buildMiterContext(lineWidthMultiplier: lineWidthMultiplier)
        case .curves:
            return buildCurvesContext(lineWidthMultiplier: lineWidthMultiplier)
        case .geometry:
            return buildGeometryContext(lineWidthMultiplier: lineWidthMultiplier)
        case .randomLines:
            return buildRandomLinesContext(lineWidthMultiplier: lineWidthMultiplier, lines: randomLines)
        }
    }

    private func buildLineCapsContext(lineWidthMultiplier: Double) -> GraphicsContext3D {
        GraphicsContext3D { context in
            let z: Float = 0
            let ySpacing: Float = 1
            let lineLength: Float = 6

            let buttLine = Path3D { path in
                path.move(to: [-lineLength / 2, ySpacing * 1, z])
                path.addLine(to: [lineLength / 2, ySpacing * 1, z])
            }
            context.stroke(buttLine, with: .white, style: StrokeStyle(lineWidth: 40.0 * lineWidthMultiplier, lineCap: .butt))

            let roundLine = Path3D { path in
                path.move(to: [-lineLength / 2, 0, z])
                path.addLine(to: [lineLength / 2, 0, z])
            }
            context.stroke(roundLine, with: .orange, style: StrokeStyle(lineWidth: 40.0 * lineWidthMultiplier, lineCap: .round))

            let squareLine = Path3D { path in
                path.move(to: [-lineLength / 2, -ySpacing * 1, z])
                path.addLine(to: [lineLength / 2, -ySpacing * 1, z])
            }
            context.stroke(squareLine, with: .cyan, style: StrokeStyle(lineWidth: 40.0 * lineWidthMultiplier, lineCap: .square))
        }
    }

    private func buildLineJoinsContext(lineWidthMultiplier: Double) -> GraphicsContext3D {
        GraphicsContext3D { context in
            let spacing: Float = 3.5

            let miterSquare = Path3D { path in
                path.move(to: [-1 + spacing * -1, -1, -1])
                path.addLine(to: [ 1 + spacing * -1, -1, -1])
                path.addLine(to: [ 1 + spacing * -1, 1, -1])
                path.addLine(to: [-1 + spacing * -1, 1, -1])
                path.closeSubpath()
            }
            context.stroke(miterSquare, with: .red, style: StrokeStyle(lineWidth: 40.0 * lineWidthMultiplier, lineCap: .butt, lineJoin: .miter))

            let roundSquare = Path3D { path in
                path.move(to: [-1 + spacing * 0, -1, -1])
                path.addLine(to: [ 1 + spacing * 0, -1, -1])
                path.addLine(to: [ 1 + spacing * 0, 1, -1])
                path.addLine(to: [-1 + spacing * 0, 1, -1])
                path.closeSubpath()
            }
            context.stroke(roundSquare, with: .green, style: StrokeStyle(lineWidth: 40.0 * lineWidthMultiplier, lineCap: .butt, lineJoin: .round))

            let bevelSquare = Path3D { path in
                path.move(to: [-1 + spacing * 1, -1, -1])
                path.addLine(to: [ 1 + spacing * 1, -1, -1])
                path.addLine(to: [ 1 + spacing * 1, 1, -1])
                path.addLine(to: [-1 + spacing * 1, 1, -1])
                path.closeSubpath()
            }
            context.stroke(bevelSquare, with: .blue, style: StrokeStyle(lineWidth: 40.0 * lineWidthMultiplier, lineCap: .butt, lineJoin: .bevel))
        }
    }

    private func buildMiterContext(lineWidthMultiplier: Double) -> GraphicsContext3D {
        GraphicsContext3D { context in
            let lShape = Path3D { path in
                path.move(to: [-1, -1, -1])
                path.addLine(to: [ 1, -1, -1])
                path.addLine(to: [ 1, 1, -1])
            }
            context.stroke(lShape, with: .red, style: StrokeStyle(lineWidth: 40.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .miter))
        }
    }

    private func buildCurvesContext(lineWidthMultiplier: Double) -> GraphicsContext3D {
        GraphicsContext3D { context in
            let quadCurve = Path3D { path in
                path.move(to: [-3, -1, 0])
                path.addQuadCurve(to: [0, -1, 0], control: [-1.5, 2, 0])
            }
            context.stroke(quadCurve, with: .orange, style: StrokeStyle(lineWidth: 30.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))

            let cubicCurve = Path3D { path in
                path.move(to: [0, -1, 0])
                path.addCurve(to: [3, -1, 0], control1: [1, 2, 0], control2: [2, -2, 0])
            }
            context.stroke(cubicCurve, with: .cyan, style: StrokeStyle(lineWidth: 30.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))

            let spiralPath = Path3D { path in
                path.move(to: [-2, 1, -1])
                path.addCurve(to: [-1, 2, -1], control1: [-2, 2, -1], control2: [-1, 2, -1])
                path.addCurve(to: [0, 1, -1], control1: [-1, 1, -1], control2: [0, 1, -1])
                path.addCurve(to: [1, 2, -1], control1: [1, 2, -1], control2: [1, 2, -1])
                path.addCurve(to: [2, 1, -1], control1: [2, 1, -1], control2: [2, 1, -1])
            }
            context.stroke(spiralPath, with: .yellow, style: StrokeStyle(lineWidth: 20.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))

            let kappa: Float = 0.5522847498

            let circle1 = Path3D { path in
                let cx: Float = -2.5
                let cy: Float = -2
                let cz: Float = 1
                let r: Float = 0.8

                path.move(to: [cx + r, cy, cz])
                path.addCurve(to: [cx, cy + r, cz], control1: [cx + r, cy + r * kappa, cz], control2: [cx + r * kappa, cy + r, cz])
                path.addCurve(to: [cx - r, cy, cz], control1: [cx - r * kappa, cy + r, cz], control2: [cx - r, cy + r * kappa, cz])
                path.addCurve(to: [cx, cy - r, cz], control1: [cx - r, cy - r * kappa, cz], control2: [cx - r * kappa, cy - r, cz])
                path.addCurve(to: [cx + r, cy, cz], control1: [cx + r * kappa, cy - r, cz], control2: [cx + r, cy - r * kappa, cz])
            }
            context.stroke(circle1, with: .pink, style: StrokeStyle(lineWidth: 15.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))

            let circle2 = Path3D { path in
                let cx: Float = 0
                let cy: Float = -2.5
                let cz: Float = 1
                let r: Float = 0.5

                path.move(to: [cx + r, cy, cz])
                path.addCurve(to: [cx, cy + r, cz], control1: [cx + r, cy + r * kappa, cz], control2: [cx + r * kappa, cy + r, cz])
                path.addCurve(to: [cx - r, cy, cz], control1: [cx - r * kappa, cy + r, cz], control2: [cx - r, cy + r * kappa, cz])
                path.addCurve(to: [cx, cy - r, cz], control1: [cx - r, cy - r * kappa, cz], control2: [cx - r * kappa, cy - r, cz])
                path.addCurve(to: [cx + r, cy, cz], control1: [cx + r * kappa, cy - r, cz], control2: [cx + r, cy - r * kappa, cz])
            }
            context.stroke(circle2, with: .green, style: StrokeStyle(lineWidth: 12.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))

            let circle3 = Path3D { path in
                let cx: Float = 2.5
                let cy: Float = -2
                let cz: Float = 1
                let r: Float = 0.6

                path.move(to: [cx + r, cy, cz])
                path.addCurve(to: [cx, cy + r, cz], control1: [cx + r, cy + r * kappa, cz], control2: [cx + r * kappa, cy + r, cz])
                path.addCurve(to: [cx - r, cy, cz], control1: [cx - r * kappa, cy + r, cz], control2: [cx - r, cy + r * kappa, cz])
                path.addCurve(to: [cx, cy - r, cz], control1: [cx - r, cy - r * kappa, cz], control2: [cx - r * kappa, cy - r, cz])
                path.addCurve(to: [cx + r, cy, cz], control1: [cx + r * kappa, cy - r, cz], control2: [cx + r, cy - r * kappa, cz])
            }
            context.stroke(circle3, with: .red, style: StrokeStyle(lineWidth: 10.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))
        }
    }

    private func buildGeometryContext(lineWidthMultiplier: Double) -> GraphicsContext3D {
        GraphicsContext3D { context in
            let groundSquare = Path3D { path in
                path.move(to: [-4, -2, -4])
                path.addLine(to: [ 4, -2, -4])
                path.addLine(to: [ 4, -2, 4])
                path.addLine(to: [-4, -2, 4])
                path.closeSubpath()
            }
            context.stroke(groundSquare, with: .gray, style: StrokeStyle(lineWidth: 24.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))

            let cubeOutline = Path3D { path in
                // Bottom square
                path.move(to: [-2, -2, -2])
                path.addLine(to: [ 2, -2, -2])
                path.addLine(to: [ 2, -2, 2])
                path.addLine(to: [-2, -2, 2])
                path.closeSubpath()

                // Top square
                path.move(to: [-2, 2, -2])
                path.addLine(to: [ 2, 2, -2])
                path.addLine(to: [ 2, 2, 2])
                path.addLine(to: [-2, 2, 2])
                path.closeSubpath()

                // Vertical edges
                path.move(to: [-2, -2, -2])
                path.addLine(to: [-2, 2, -2])

                path.move(to: [ 2, -2, -2])
                path.addLine(to: [ 2, 2, -2])

                path.move(to: [ 2, -2, 2])
                path.addLine(to: [ 2, 2, 2])

                path.move(to: [-2, -2, 2])
                path.addLine(to: [-2, 2, 2])
            }
            context.stroke(cubeOutline, with: .white, style: StrokeStyle(lineWidth: 16.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))

            let triangle = Path3D { path in
                path.move(to: [0, 1, 0])
                path.addLine(to: [-1, -1, 0])
                path.addLine(to: [1, -1, 0])
                path.closeSubpath()
            }
            context.fill(triangle, with: .red)
            context.stroke(triangle, with: .white, style: StrokeStyle(lineWidth: 6.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))

            let square = Path3D { path in
                path.move(to: [-0.6, -0.6, 1])
                path.addLine(to: [ 0.6, -0.6, 1])
                path.addLine(to: [ 0.6, 0.6, 1])
                path.addLine(to: [-0.6, 0.6, 1])
                path.closeSubpath()
            }
            context.fill(square, with: .green)
            context.stroke(square, with: .white, style: StrokeStyle(lineWidth: 6.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .round))
        }
    }

    private func buildRandomLinesContext(lineWidthMultiplier: Double, lines: [(start: SIMD3<Float>, end: SIMD3<Float>, color: Color)]) -> GraphicsContext3D {
        GraphicsContext3D { context in
            for lineData in lines {
                let line = Path3D { path in
                    path.move(to: lineData.start)
                    path.addLine(to: lineData.end)
                }
                context.stroke(line, with: lineData.color, style: StrokeStyle(lineWidth: 2.0 * lineWidthMultiplier, lineCap: .butt))
            }
        }
    }
}
