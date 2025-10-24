import SwiftUI
import Ultraviolence
import UltraviolenceUI

public struct MetalCanvasDemoView: View {
    enum DemoType: String, CaseIterable, Identifiable {
        case rectangleAndCircle = "Rectangle & Circle"
        case triangle = "Triangle"
        case randomLines = "Random Lines"

        var id: String { rawValue }
    }

    @State
    private var lineWidth: Float = 2.0

    @State
    private var selectedDemo: DemoType = .randomLines

    public init() {
        // This line intentionally left blank.
    }

    public var body: some View {
        VStack {
            RenderView { _, drawableSize in
                let canvas = makeCanvas(for: selectedDemo)
                let viewport = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))

                try RenderPass {
                    try MetalCanvasRenderPipeline(canvas: canvas, viewport: viewport, limits: .init(maxDrawOperations: 16_384))
                }
            }

            HStack {
                Text("Line Width: \(lineWidth, format: .number.precision(.fractionLength(1)))")
                Slider(value: $lineWidth, in: 1...10)
            }
            .padding()
        }
        .toolbar {
            Picker("Demo", selection: $selectedDemo) {
                ForEach(DemoType.allCases) { demo in
                    Text(demo.rawValue).tag(demo)
                }
            }
        }
    }

    func makeCanvas(for demo: DemoType) -> MetalCanvas {
        switch demo {
        case .rectangleAndCircle:
            return MetalCanvas { context in
                var path = Path()
                path.move(to: CGPoint(x: 100, y: 100))
                path.addLine(to: CGPoint(x: 300, y: 100))
                path.addLine(to: CGPoint(x: 300, y: 300))
                path.addLine(to: CGPoint(x: 100, y: 300))
                path.closeSubpath()
                context.stroke(path, with: .red, lineWidth: lineWidth)

                var circlePath = Path()
                circlePath.addEllipse(in: CGRect(x: 400, y: 200, width: 200, height: 200))
                context.stroke(circlePath, with: .blue, lineWidth: lineWidth)
            }

        case .triangle:
            return MetalCanvas { context in
                var path = Path()
                path.move(to: CGPoint(x: 400, y: 150))
                path.addLine(to: CGPoint(x: 550, y: 400))
                path.addLine(to: CGPoint(x: 250, y: 400))
                path.closeSubpath()
                context.stroke(path, with: .green, lineWidth: lineWidth)
            }

        case .randomLines:
            let canvas = MetalCanvas { context in
                for i in 0..<8_192 {
                    var path = Path()
                    let x1 = CGFloat.random(in: 50...2_000)
                    let y1 = CGFloat.random(in: 50...2_000)
                    let x2 = CGFloat.random(in: 50...2_000)
                    let y2 = CGFloat.random(in: 50...2_000)
                    path.move(to: CGPoint(x: x1, y: y1))
                    path.addLine(to: CGPoint(x: x2, y: y2))
                    // Use fixed white color to make them visible
                    context.stroke(path, with: .white, lineWidth: lineWidth)
                }
            }
            print("Random lines canvas created with \(canvas.operations.count) operations")
            return canvas
        }
    }
}
