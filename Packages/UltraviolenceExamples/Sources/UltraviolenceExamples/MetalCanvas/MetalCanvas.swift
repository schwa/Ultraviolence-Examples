import Metal
import SwiftUI
import UltraviolenceExampleShaders

public struct MetalCanvas: Equatable {
    internal enum DrawOperation: Equatable {
        case stroke(path: Path, color: SIMD4<Float>, lineWidth: Float)
    }

    internal var operations: [DrawOperation] = []

    public init() {
        // This line intentionally left blank.
    }

    public init(_ builder: (inout Self) -> Void) {
        builder(&self)
    }

    public mutating func stroke(_ path: Path, with color: Color, lineWidth: Float) {
        let resolved = color.resolve(in: .init())
        let colorVector = SIMD4<Float>(resolved.red, resolved.green, resolved.blue, resolved.opacity)
        operations.append(.stroke(path: path, color: colorVector, lineWidth: lineWidth))
    }
}
