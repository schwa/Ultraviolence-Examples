import simd

struct Path3D: Equatable {
    enum Element: Equatable {
        case move(to: SIMD3<Float>)
        case line(to: SIMD3<Float>)
        case quadCurve(to: SIMD3<Float>, control: SIMD3<Float>)
        case curve(to: SIMD3<Float>, control1: SIMD3<Float>, control2: SIMD3<Float>)
        case closeSubpath
    }

    private var elements: [Element] = []

    init() {
        // Empty initializer
    }

    init(_ builder: (inout Self) -> Void) {
        builder(&self)
    }

    mutating func move(to point: SIMD3<Float>) {
        elements.append(.move(to: point))
    }

    mutating func addLine(to point: SIMD3<Float>) {
        elements.append(.line(to: point))
    }

    mutating func addQuadCurve(to point: SIMD3<Float>, control: SIMD3<Float>) {
        elements.append(.quadCurve(to: point, control: control))
    }

    mutating func addCurve(to point: SIMD3<Float>, control1: SIMD3<Float>, control2: SIMD3<Float>) {
        elements.append(.curve(to: point, control1: control1, control2: control2))
    }

    mutating func closeSubpath() {
        elements.append(.closeSubpath)
    }

    func getElements() -> [Element] {
        elements
    }
}
