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

    public init() {
        // Empty initializer
    }

    public var body: some View {
        WorldView(projection: $projection, cameraMatrix: $cameraMatrix) {
            Group {
                if isPlaying {
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
        }
        .toolbar {
            ToolbarItem {
                Picker("Sample", selection: $selectedSample) {
                    ForEach(Sample.allCases) { sample in
                        Text(sample.rawValue).tag(sample)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button(action: { isPlaying.toggle() }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
            }
            ToolbarItem {
                Button(action: { debugWireframe.toggle() }) {
                    Image(systemName: debugWireframe ? "grid.circle.fill" : "grid.circle")
                }
            }
            ToolbarItem {
                Button(action: {
                    cameraMatrix = .init(translation: [0, 0, 8])
                    rotation = 0.0
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
            ToolbarItem {
                Button(action: { showLineWidthPopover.toggle() }) {
                    Image(systemName: "lineweight")
                }
                .popover(isPresented: $showLineWidthPopover) {
                    VStack {
                        Text("Line Width Multiplier")
                            .font(.headline)
                        Slider(value: $lineWidthMultiplier, in: 0.1...5.0)
                        Text(String(format: "%.2f", lineWidthMultiplier))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(minWidth: 200)
                }
            }
        }
    }

    private func buildLineCapsContext() -> GraphicsContext3D {
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

    private func buildLineJoinsContext() -> GraphicsContext3D {
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

    private func buildMiterContext() -> GraphicsContext3D {
        GraphicsContext3D { context in
            let lShape = Path3D { path in
                path.move(to: [-1, -1, -1])
                path.addLine(to: [ 1, -1, -1])
                path.addLine(to: [ 1, 1, -1])
            }
            context.stroke(lShape, with: .red, style: StrokeStyle(lineWidth: 40.0 * lineWidthMultiplier, lineCap: .round, lineJoin: .miter))
        }
    }

    private func buildCurvesContext() -> GraphicsContext3D {
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

    private func buildGeometryContext() -> GraphicsContext3D {
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

    private var currentContext: GraphicsContext3D {
        switch selectedSample {
        case .lineCaps:
            return buildLineCapsContext()
        case .lineJoins:
            return buildLineJoinsContext()
        case .miter:
            return buildMiterContext()
        case .curves:
            return buildCurvesContext()
        case .geometry:
            return buildGeometryContext()
        }
    }

    @ViewBuilder
    private func renderContent(animating: Bool) -> some View {
        RenderView { _, drawableSize in
            let projectionMatrix = projection.projectionMatrix(for: drawableSize)
            let viewMatrix = cameraMatrix.inverse
            let rotationMatrix = animating ? float4x4(yRotation: .radians(rotation)) : .identity
            let viewProjection = projectionMatrix * viewMatrix * rotationMatrix

            try RenderPass {
                try GraphicsContext3DRenderPipeline(context: currentContext, viewProjection: viewProjection, viewport: [Float(drawableSize.width), Float(drawableSize.height)], debugWireframe: debugWireframe)
            }
        }
        .metalDepthStencilPixelFormat(.depth32Float)
    }
}
