import Metal
import SwiftUI
import UltraviolenceExampleShaders

struct MetalCanvasOperations {
    struct Limits {
        let maxDrawOperations: Int
        let maxSegments: Int
        let maxSegmentsPerOperation: Int

        init(maxDrawOperations: Int = 1_024, maxSegments: Int = 16 * 1_024, maxSegmentsPerOperation: Int = 1_024) {
            self.maxDrawOperations = maxDrawOperations
            self.maxSegments = maxSegments
            self.maxSegmentsPerOperation = maxSegmentsPerOperation
        }
    }

    enum ExpandError: Error {
        case drawOperationsBufferFull(count: Int)
        case segmentOffsetsBufferFull(count: Int)
        case tooManySegmentsPerOperation(count: Int, limit: Int)
    }

    enum BufferCreationError: Error {
        case failedToCreateBuffer(String)
    }

    let drawOperationsBuffer: MTLBuffer
    let segmentOffsetsBuffer: MTLBuffer
    let segmentsBuffer: MTLBuffer
    let limits: Limits

    init(device: MTLDevice, limits: Limits = Limits()) throws {
        self.limits = limits

        let drawOperationsBufferSize = limits.maxDrawOperations * MemoryLayout<MetalCanvasDrawOperation>.stride
        guard let drawOpsBuffer = device.makeBuffer(length: drawOperationsBufferSize, options: .storageModeShared) else {
            throw BufferCreationError.failedToCreateBuffer("draw operations buffer")
        }
        drawOperationsBuffer = drawOpsBuffer

        let segmentOffsetsBufferSize = limits.maxSegments * MemoryLayout<UInt32>.stride
        guard let segOffsetsBuffer = device.makeBuffer(length: segmentOffsetsBufferSize, options: .storageModeShared) else {
            throw BufferCreationError.failedToCreateBuffer("segment offsets buffer")
        }
        segmentOffsetsBuffer = segOffsetsBuffer

        let segmentsBufferSize = 16 * 1_024 * 1_024
        guard let segsBuffer = device.makeBuffer(length: segmentsBufferSize, options: .storageModeShared) else {
            throw BufferCreationError.failedToCreateBuffer("segments buffer")
        }
        segmentsBuffer = segsBuffer

        drawOperationsBuffer.label = "MetalCanvas Draw Operations Buffer"
        segmentOffsetsBuffer.label = "MetalCanvas Segment Offsets Buffer"
        segmentsBuffer.label = "MetalCanvas Segments Buffer"
    }

    func expand(canvas: MetalCanvas) throws -> Int {
        let drawOperationsPointer = UnsafeMutableBufferPointer(start: drawOperationsBuffer.contents().assumingMemoryBound(to: MetalCanvasDrawOperation.self), count: drawOperationsBuffer.length / MemoryLayout<MetalCanvasDrawOperation>.stride)
        let segmentOffsetsPointer = UnsafeMutableBufferPointer(start: segmentOffsetsBuffer.contents().assumingMemoryBound(to: UInt32.self), count: segmentOffsetsBuffer.length / MemoryLayout<UInt32>.stride)
        let segmentsPointer = UnsafeMutableRawBufferPointer(start: segmentsBuffer.contents(), count: segmentsBuffer.length)
        let result = try expand(canvas: canvas, drawOperations: drawOperationsPointer, segmentOffsets: segmentOffsetsPointer, segments: segmentsPointer)
        print("Expanded \(canvas.operations.count) canvas operations into \(result) draw operations")
        return result
    }

    private func expand(canvas: MetalCanvas, drawOperations: UnsafeMutableBufferPointer<MetalCanvasDrawOperation>, segmentOffsets: UnsafeMutableBufferPointer<UInt32>, segments: UnsafeMutableRawBufferPointer) throws -> Int {
        guard let segmentsBase = segments.baseAddress else {
            return 0
        }

        var drawOperationIndex = 0
        var segmentIndex = 0

        for case let .stroke(path, color, lineWidth) in canvas.operations {
            guard drawOperationIndex < drawOperations.count else {
                throw ExpandError.drawOperationsBufferFull(count: drawOperations.count)
            }

            let startSegmentIndex = segmentIndex

            var currentPoint = CGPoint.zero
            var subpathStart = CGPoint.zero

            path.forEach { element in
                switch element {
                case let .move(to):
                    currentPoint = to
                    subpathStart = to

                case let .line(to):
                    guard segmentIndex < segmentOffsets.count else {
                        return
                    }
                    let segment = MetalCanvasLineSegment(start: SIMD2<Float>(Float(currentPoint.x), Float(currentPoint.y)), end: SIMD2<Float>(Float(to.x), Float(to.y)))
                    segmentOffsets[segmentIndex] = UInt32(MetalCanvasSegmentType.line.rawValue)
                    let segmentPointer = (segmentsBase + segmentIndex * MemoryLayout<MetalCanvasLineSegment>.stride).bindMemory(to: MetalCanvasLineSegment.self, capacity: 1)
                    segmentPointer.pointee = segment
                    segmentIndex += 1
                    currentPoint = to

                case let .quadCurve(to, control):
                    guard segmentIndex < segmentOffsets.count else {
                        return
                    }
                    // Convert quad curve to cubic curve
                    // Quadratic: P(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
                    // Cubic: P(t) = (1-t)³P₀ + 3(1-t)²tC₁ + 3(1-t)t²C₂ + t³P₃
                    // C₁ = P₀ + 2/3(P₁ - P₀)
                    // C₂ = P₂ + 2/3(P₁ - P₂)
                    let p0 = currentPoint
                    let p1 = control
                    let p2 = to
                    let c1 = CGPoint(x: p0.x + 2.0 / 3.0 * (p1.x - p0.x), y: p0.y + 2.0 / 3.0 * (p1.y - p0.y))
                    let c2 = CGPoint(x: p2.x + 2.0 / 3.0 * (p1.x - p2.x), y: p2.y + 2.0 / 3.0 * (p1.y - p2.y))

                    let curve = MetalCanvasCubicCurve(start: SIMD2<Float>(Float(p0.x), Float(p0.y)), control1: SIMD2<Float>(Float(c1.x), Float(c1.y)), control2: SIMD2<Float>(Float(c2.x), Float(c2.y)), end: SIMD2<Float>(Float(p2.x), Float(p2.y)))
                    segmentOffsets[segmentIndex] = UInt32(MetalCanvasSegmentType.cubicCurve.rawValue)
                    let curvePointer = (segmentsBase + segmentIndex * MemoryLayout<MetalCanvasCubicCurve>.stride).bindMemory(to: MetalCanvasCubicCurve.self, capacity: 1)
                    curvePointer.pointee = curve
                    segmentIndex += 1
                    currentPoint = to

                case let .curve(to, control1, control2):
                    guard segmentIndex < segmentOffsets.count else {
                        return
                    }
                    let curve = MetalCanvasCubicCurve(start: SIMD2<Float>(Float(currentPoint.x), Float(currentPoint.y)), control1: SIMD2<Float>(Float(control1.x), Float(control1.y)), control2: SIMD2<Float>(Float(control2.x), Float(control2.y)), end: SIMD2<Float>(Float(to.x), Float(to.y)))
                    segmentOffsets[segmentIndex] = UInt32(MetalCanvasSegmentType.cubicCurve.rawValue)
                    let curvePointer = (segmentsBase + segmentIndex * MemoryLayout<MetalCanvasCubicCurve>.stride).bindMemory(to: MetalCanvasCubicCurve.self, capacity: 1)
                    curvePointer.pointee = curve
                    segmentIndex += 1
                    currentPoint = to

                case .closeSubpath:
                    if currentPoint != subpathStart {
                        guard segmentIndex < segmentOffsets.count else {
                            return
                        }
                        let segment = MetalCanvasLineSegment(start: SIMD2<Float>(Float(currentPoint.x), Float(currentPoint.y)), end: SIMD2<Float>(Float(subpathStart.x), Float(subpathStart.y)))
                        segmentOffsets[segmentIndex] = UInt32(MetalCanvasSegmentType.line.rawValue)
                        let segmentPointer = (segmentsBase + segmentIndex * MemoryLayout<MetalCanvasLineSegment>.stride).bindMemory(to: MetalCanvasLineSegment.self, capacity: 1)
                        segmentPointer.pointee = segment
                        segmentIndex += 1
                        currentPoint = subpathStart
                    }
                }
            }

            let segmentCount = segmentIndex - startSegmentIndex
            guard segmentCount <= limits.maxSegmentsPerOperation else {
                throw ExpandError.tooManySegmentsPerOperation(count: segmentCount, limit: limits.maxSegmentsPerOperation)
            }
            guard segmentIndex <= segmentOffsets.count else {
                throw ExpandError.segmentOffsetsBufferFull(count: segmentOffsets.count)
            }
            drawOperations[drawOperationIndex] = MetalCanvasDrawOperation(color: color, lineWidth: lineWidth, segmentIndex: UInt32(startSegmentIndex), segmentCount: UInt32(segmentCount))
            drawOperationIndex += 1
        }
        return drawOperationIndex
    }
}
