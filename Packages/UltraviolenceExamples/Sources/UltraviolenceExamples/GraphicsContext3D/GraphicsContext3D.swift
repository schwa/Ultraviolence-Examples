import simd
import CoreGraphics

// GraphicsContext3D: A SwiftUI.Canvas-style API for rendering stroked and filled paths in 3D with pixel-perfect line widths.
// - GraphicsContext3D: Records stroke() and fill() commands with Path3D objects and styles
// - Path3D: Defines 3D paths using move/line/closeSubpath operations
// - GeometryGenerator: Transforms paths to screen space, generates triangulated geometry for line segments, round/square/butt caps, and miter/round/bevel joins
// - Line rendering uses screen-space geometry: 3D points → clip space → NDC → screen pixels (generate quads/caps/joins) → back to clip space
// - GraphicsContext3DRenderPipeline: Renders all generated geometry as a single triangle list with depth testing
// - StrokeStyle: Controls line width, cap style (.butt/.round/.square), join style (.miter/.round/.bevel), and miter limit

public struct GraphicsContext3D: Equatable {
    internal enum DrawCommand: Equatable {
        case stroke(path: Path3D, color: SIMD4<Float>, style: StrokeStyle)
        case fill(path: Path3D, color: SIMD4<Float>)
    }

    internal private(set) var commands: [DrawCommand] = []

    public init() {}

    public init(_ builder: (inout GraphicsContext3D) -> Void) {
        builder(&self)
    }

    public mutating func stroke(_ path: Path3D, with color: SIMD4<Float>, style: StrokeStyle) {
        commands.append(.stroke(path: path, color: color, style: style))
    }

    public mutating func stroke(_ path: Path3D, with color: SIMD4<Float>, lineWidth: Float) {
        commands.append(.stroke(path: path, color: color, style: StrokeStyle(lineWidth: CGFloat(lineWidth))))
    }

    public mutating func fill(_ path: Path3D, with color: SIMD4<Float>) {
        commands.append(.fill(path: path, color: color))
    }
}
