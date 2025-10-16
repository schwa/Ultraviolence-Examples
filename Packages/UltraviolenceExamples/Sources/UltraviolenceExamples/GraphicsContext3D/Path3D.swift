import simd

public struct Path3D: Equatable {
    public enum Element: Equatable {
        case move(to: SIMD3<Float>)
        case line(to: SIMD3<Float>)
        case quadCurve(to: SIMD3<Float>, control: SIMD3<Float>)
        case curve(to: SIMD3<Float>, control1: SIMD3<Float>, control2: SIMD3<Float>)
        case closeSubpath
    }

    private var elements: [Element] = []

    public init() {
        // Empty initializer
    }

    public init(_ builder: (inout Self) -> Void) {
        builder(&self)
    }

    public mutating func move(to point: SIMD3<Float>) {
        elements.append(.move(to: point))
    }

    public mutating func addLine(to point: SIMD3<Float>) {
        elements.append(.line(to: point))
    }

    public mutating func addQuadCurve(to point: SIMD3<Float>, control: SIMD3<Float>) {
        elements.append(.quadCurve(to: point, control: control))
    }

    public mutating func addCurve(to point: SIMD3<Float>, control1: SIMD3<Float>, control2: SIMD3<Float>) {
        elements.append(.curve(to: point, control1: control1, control2: control2))
    }

    public mutating func closeSubpath() {
        elements.append(.closeSubpath)
    }

    public func getElements() -> [Element] {
        elements
    }
}
