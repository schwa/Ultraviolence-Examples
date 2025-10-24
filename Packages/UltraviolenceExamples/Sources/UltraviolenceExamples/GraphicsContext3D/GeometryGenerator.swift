import CoreGraphics
import earcut
import simd
import UltraviolenceExampleShaders

internal struct Vertex {
    // periphery:ignore - used in Metal shader
    var position: SIMD3<Float>
    // periphery:ignore - used in Metal shader
    var color: SIMD4<Float>
}

internal struct GeometryGenerator {
    let viewProjection: float4x4
    let viewport: SIMD2<Float>

    private func estimateQuadCurveScreenLength(from p0: SIMD3<Float>, to p2: SIMD3<Float>, control p1: SIMD3<Float>) -> Float {
        let p0Clip = viewProjection * SIMD4<Float>(p0, 1.0)
        let p1Clip = viewProjection * SIMD4<Float>(p1, 1.0)
        let p2Clip = viewProjection * SIMD4<Float>(p2, 1.0)

        guard abs(p0Clip.w) > 1e-6, abs(p1Clip.w) > 1e-6, abs(p2Clip.w) > 1e-6 else {
            return 0
        }

        let p0Screen = SIMD2<Float>((p0Clip.x / p0Clip.w * 0.5 + 0.5) * viewport.x, (p0Clip.y / p0Clip.w * 0.5 + 0.5) * viewport.y)
        let p1Screen = SIMD2<Float>((p1Clip.x / p1Clip.w * 0.5 + 0.5) * viewport.x, (p1Clip.y / p1Clip.w * 0.5 + 0.5) * viewport.y)
        let p2Screen = SIMD2<Float>((p2Clip.x / p2Clip.w * 0.5 + 0.5) * viewport.x, (p2Clip.y / p2Clip.w * 0.5 + 0.5) * viewport.y)

        let chordLength = distance(p0Screen, p2Screen)
        let controlLength = distance(p0Screen, p1Screen) + distance(p1Screen, p2Screen)
        return (chordLength + controlLength) / 2
    }

    private func estimateCubicCurveScreenLength(from p0: SIMD3<Float>, to p3: SIMD3<Float>, control1 p1: SIMD3<Float>, control2 p2: SIMD3<Float>) -> Float {
        let p0Clip = viewProjection * SIMD4<Float>(p0, 1.0)
        let p1Clip = viewProjection * SIMD4<Float>(p1, 1.0)
        let p2Clip = viewProjection * SIMD4<Float>(p2, 1.0)
        let p3Clip = viewProjection * SIMD4<Float>(p3, 1.0)

        guard abs(p0Clip.w) > 1e-6, abs(p1Clip.w) > 1e-6, abs(p2Clip.w) > 1e-6, abs(p3Clip.w) > 1e-6 else {
            return 0
        }

        let p0Screen = SIMD2<Float>((p0Clip.x / p0Clip.w * 0.5 + 0.5) * viewport.x, (p0Clip.y / p0Clip.w * 0.5 + 0.5) * viewport.y)
        let p1Screen = SIMD2<Float>((p1Clip.x / p1Clip.w * 0.5 + 0.5) * viewport.x, (p1Clip.y / p1Clip.w * 0.5 + 0.5) * viewport.y)
        let p2Screen = SIMD2<Float>((p2Clip.x / p2Clip.w * 0.5 + 0.5) * viewport.x, (p2Clip.y / p2Clip.w * 0.5 + 0.5) * viewport.y)
        let p3Screen = SIMD2<Float>((p3Clip.x / p3Clip.w * 0.5 + 0.5) * viewport.x, (p3Clip.y / p3Clip.w * 0.5 + 0.5) * viewport.y)

        let chordLength = distance(p0Screen, p3Screen)
        let controlLength = distance(p0Screen, p1Screen) + distance(p1Screen, p2Screen) + distance(p2Screen, p3Screen)
        return (chordLength + controlLength) / 2
    }

    private func subdivideQuadCurve(from p0: SIMD3<Float>, to p2: SIMD3<Float>, control p1: SIMD3<Float>, segments: Int = 20) -> [SIMD3<Float>] {
        let screenLength = estimateQuadCurveScreenLength(from: p0, to: p2, control: p1)
        let pixelsPerSegment: Float = 8.0
        let adaptiveSegments = max(3, min(40, Int(ceil(screenLength / pixelsPerSegment))))
        let segmentCount = segments == 20 ? adaptiveSegments : segments

        var points: [SIMD3<Float>] = []
        for i in 1...segmentCount {
            let t = Float(i) / Float(segmentCount)
            let mt = 1 - t
            let point = mt * mt * p0 + 2 * mt * t * p1 + t * t * p2
            points.append(point)
        }
        return points
    }

    private func subdivideCubicCurve(from p0: SIMD3<Float>, to p3: SIMD3<Float>, control1 p1: SIMD3<Float>, control2 p2: SIMD3<Float>, segments: Int = 20) -> [SIMD3<Float>] {
        let screenLength = estimateCubicCurveScreenLength(from: p0, to: p3, control1: p1, control2: p2)
        let pixelsPerSegment: Float = 8.0
        let adaptiveSegments = max(3, min(40, Int(ceil(screenLength / pixelsPerSegment))))
        let segmentCount = segments == 20 ? adaptiveSegments : segments

        var points: [SIMD3<Float>] = []
        for i in 1...segmentCount {
            let t = Float(i) / Float(segmentCount)
            let mt = 1 - t
            let point = mt * mt * mt * p0 + 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t * p3
            points.append(point)
        }
        return points
    }

    func generateFillGeometry(path: Path3D, color: SIMD4<Float>) -> [Vertex] {
        let points = extractPoints(from: path)
        guard points.count >= 3 else {
            fatalError("Fill requires at least 3 points, got \(points.count)")
        }

        let projectedPoints = points.map { SIMD2<Float>($0.x, $0.y) }
        let indices = earcut(polygons: [projectedPoints])

        var vertices: [Vertex] = []
        for i in stride(from: 0, to: indices.count, by: 3) {
            let idx0 = Int(indices[i])
            let idx1 = Int(indices[i + 1])
            let idx2 = Int(indices[i + 2])

            let p0Clip = viewProjection * SIMD4<Float>(points[idx0], 1.0)
            let p1Clip = viewProjection * SIMD4<Float>(points[idx1], 1.0)
            let p2Clip = viewProjection * SIMD4<Float>(points[idx2], 1.0)

            let p0NDC = p0Clip.xyz / p0Clip.w
            let p1NDC = p1Clip.xyz / p1Clip.w
            let p2NDC = p2Clip.xyz / p2Clip.w

            vertices.append(Vertex(position: p0NDC, color: color))
            vertices.append(Vertex(position: p1NDC, color: color))
            vertices.append(Vertex(position: p2NDC, color: color))
        }

        return vertices
    }

    private func extractPoints(from path: Path3D) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        var currentPoint: SIMD3<Float>?

        for element in path.getElements() {
            switch element {
            case .move(let to):
                currentPoint = to
                points.append(to)
            case .line(let to):
                guard currentPoint != nil else {
                    fatalError("Line command without preceding move command")
                }
                points.append(to)
                currentPoint = to
            case let .quadCurve(to, control):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }
                let curvePoints = subdivideQuadCurve(from: from, to: to, control: control)
                points.append(contentsOf: curvePoints)
                currentPoint = to
            case let .curve(to, control1, control2):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }
                let curvePoints = subdivideCubicCurve(from: from, to: to, control1: control1, control2: control2)
                points.append(contentsOf: curvePoints)
                currentPoint = to
            case .closeSubpath:
                break
            }
        }

        return points
    }

    private func generateJoinDataForSubpath(segments: [(start: SIMD3<Float>, end: SIMD3<Float>)], isLoop: Bool, lineWidth: Float, joinStyleValue: UInt32, capStyleValue: UInt32, color: SIMD4<Float>, miterLimit: Float) -> [LineJoinGPUData] {
        guard !segments.isEmpty else {
            return []
        }

        var joinData: [LineJoinGPUData] = []
        let pointCount = isLoop ? segments.count : segments.count + 1

        for i in 0..<pointCount {
            let prevPoint: SIMD3<Float>
            let joinPoint: SIMD3<Float>
            let nextPoint: SIMD3<Float>
            let isStartCap: UInt32
            let isEndCap: UInt32

            if i == 0, !isLoop {
                // Start cap
                joinPoint = segments[0].start
                prevPoint = joinPoint  // Dummy, not used for start cap
                nextPoint = segments[0].end
                isStartCap = 1
                isEndCap = 0
            } else if i == segments.count, !isLoop {
                // End cap
                joinPoint = segments[segments.count - 1].end
                prevPoint = segments[segments.count - 1].start
                nextPoint = joinPoint  // Dummy, not used for end cap
                isStartCap = 0
                isEndCap = 1
            } else {
                // Interior join - connecting two segments
                let incomingSegIndex = isLoop ? (i == 0 ? segments.count - 1 : i - 1) : (i - 1)
                let outgoingSegIndex = isLoop ? i : i

                joinPoint = segments[incomingSegIndex].end
                prevPoint = segments[incomingSegIndex].start
                nextPoint = segments[outgoingSegIndex].end
                isStartCap = 0
                isEndCap = 0
            }

            joinData.append(LineJoinGPUData(
                prevPoint: prevPoint,
                joinPoint: joinPoint,
                nextPoint: nextPoint,
                lineWidth: lineWidth,
                joinStyle: joinStyleValue,
                capStyle: capStyleValue,
                isStartCap: isStartCap,
                isEndCap: isEndCap,
                color: color,
                miterLimit: miterLimit,
                _padding: (0, 0, 0)
            ))
        }

        return joinData
    }

    func generateLineJoinGPUData(path: Path3D, color: SIMD4<Float>, style: StrokeStyle) -> [LineJoinGPUData] {
        var joinData: [LineJoinGPUData] = []
        let lineWidth = Float(style.lineWidth)
        let elements = path.getElements()

        let joinStyleValue: UInt32 = switch style.lineJoin {
        case .miter: 0
        case .round: 1
        case .bevel: 2
        @unknown default: 0
        }

        let capStyleValue: UInt32 = switch style.lineCap {
        case .butt: 1
        case .round: 2
        case .square: 3
        @unknown default: 1
        }

        var currentPoint: SIMD3<Float>?
        var subpathStart: SIMD3<Float>?
        var segments: [(start: SIMD3<Float>, end: SIMD3<Float>)] = []
        var isLoop = false

        func processCurrentSubpath() {
            if !segments.isEmpty {
                let subpathJoinData = generateJoinDataForSubpath(
                    segments: segments,
                    isLoop: isLoop,
                    lineWidth: lineWidth,
                    joinStyleValue: joinStyleValue,
                    capStyleValue: capStyleValue,
                    color: color,
                    miterLimit: Float(style.miterLimit)
                )
                joinData.append(contentsOf: subpathJoinData)
                segments = []
                isLoop = false
            }
        }

        for element in elements {
            switch element {
            case .move(let to):
                // Process previous subpath if any
                processCurrentSubpath()
                currentPoint = to
                subpathStart = to
            case .line(let to):
                guard let from = currentPoint else {
                    fatalError("Line command without preceding move command")
                }
                segments.append((start: from, end: to))
                currentPoint = to
            case let .quadCurve(to, control):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }
                let curvePoints = subdivideQuadCurve(from: from, to: to, control: control)
                var segmentStart = from
                for segmentEnd in curvePoints {
                    segments.append((start: segmentStart, end: segmentEnd))
                    segmentStart = segmentEnd
                }
                currentPoint = to
            case let .curve(to, control1, control2):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }
                let curvePoints = subdivideCubicCurve(from: from, to: to, control1: control1, control2: control2)
                var segmentStart = from
                for segmentEnd in curvePoints {
                    segments.append((start: segmentStart, end: segmentEnd))
                    segmentStart = segmentEnd
                }
                currentPoint = to
            case .closeSubpath:
                if let from = currentPoint, let start = subpathStart, from != start {
                    segments.append((start: from, end: start))
                }
                isLoop = true
            }
        }

        // Process final subpath
        processCurrentSubpath()

        return joinData
    }
}
