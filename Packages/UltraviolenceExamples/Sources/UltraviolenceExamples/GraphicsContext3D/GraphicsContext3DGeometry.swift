import simd
import earcut
import CoreGraphics

internal struct Vertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
}

// MARK: - Future Mesh Shader Implementation
//
// Current approach: CPU-based geometry generation
// - Path3D → CPU generates all triangles → Upload vertex buffer to GPU → Simple vertex shader → Fragment shader
//
// Future mesh shader approach (requires Ultraviolence mesh shader support):
//
// 1. Input to GPU (compact):
//    - Path commands (move/line/curve positions + control points)
//    - Stroke styles (line width, cap style, join style, miter limit)
//    - Colors per path
//    - View-projection matrix + viewport
//
// 2. Object shader (amplification stage):
//    - Process path commands
//    - Spawn meshlets: one per segment, cap, or join
//    - Pass segment info (start point, end point, direction, style) to mesh shader
//
// 3. Mesh shader:
//    - Receive segment info
//    - Generate screen-space geometry on GPU:
//      * Transform 3D points to screen space
//      * Generate line quads with perpendiculars
//      * Generate caps (round/square/butt) with adaptive segment count based on screen-space radius
//      * Generate joins (miter/round/bevel) with adaptive segment count
//      * Subdivide curves based on screen-space arc length
//    - Output vertices + primitives directly (no vertex buffer)
//
// 4. Benefits:
//    - 100x smaller upload (path data vs full vertex buffer)
//    - GPU-side adaptive LOD based on screen-space size
//    - Better for animated/dynamic paths
//    - No CPU geometry generation overhead
//    - Vertex buffer caching not needed
//
// 5. Requirements for Ultraviolence:
//    - Metal mesh shader pipeline support (Metal 3.1+)
//    - New pipeline state creation APIs
//    - Object shader + mesh shader function binding
//    - Meshlet output format handling
//
// 6. Challenges:
//    - Requires A17 Pro / M3+ hardware (iOS 17.4+, macOS 14.4+)
//    - All geometry logic must be rewritten in MSL
//    - Harder to debug (GPU-side generation)
//    - More complex pipeline setup
//    - Need to port Bezier subdivision, miter intersection, etc. to GPU

internal struct GeometryGenerator {
    let viewProjection: float4x4
    let viewport: SIMD2<Float>

    private func segmentCount(for radius: Float) -> Int {
        if radius < 2 {
            return 3
        } else if radius < 5 {
            return 4
        } else if radius < 10 {
            return 6
        } else if radius < 20 {
            return 8
        } else if radius < 40 {
            return 12
        } else {
            return 16
        }
    }

    private func estimateQuadCurveScreenLength(from p0: SIMD3<Float>, to p2: SIMD3<Float>, control p1: SIMD3<Float>) -> Float {
        let p0Clip = viewProjection * SIMD4<Float>(p0, 1.0)
        let p1Clip = viewProjection * SIMD4<Float>(p1, 1.0)
        let p2Clip = viewProjection * SIMD4<Float>(p2, 1.0)

        guard abs(p0Clip.w) > 1e-6, abs(p1Clip.w) > 1e-6, abs(p2Clip.w) > 1e-6 else { return 0 }

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

        guard abs(p0Clip.w) > 1e-6, abs(p1Clip.w) > 1e-6, abs(p2Clip.w) > 1e-6, abs(p3Clip.w) > 1e-6 else { return 0 }

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

    func generateStrokeGeometry(path: Path3D, color: SIMD4<Float>, style: StrokeStyle) -> [Vertex] {
        var vertices: [Vertex] = []
        let lineWidth = Float(style.lineWidth)
        let elements = path.getElements()

        var i = 0
        var currentPoint: SIMD3<Float>?
        var subpathStart: SIMD3<Float>?
        var subpathFirstDirection: SIMD3<Float>?
        var previousDirection: SIMD3<Float>?

        while i < elements.count {
            let element = elements[i]

            switch element {
            case .move(let to):
                if let prev = previousDirection, let current = currentPoint, style.lineCap != .butt {
                    let prevPoint = current - prev
                    let capVertices = generateEndCap(at: current, from: prevPoint, color: color, lineWidth: lineWidth, capStyle: style.lineCap, isStartCap: false)
                    vertices.append(contentsOf: capVertices)
                }
                currentPoint = to
                subpathStart = to
                subpathFirstDirection = nil
                previousDirection = nil

            case .line(let to):
                guard let from = currentPoint else {
                    fatalError("Line command without preceding move command")
                }

                let currentDirection = to - from

                if subpathFirstDirection == nil {
                    subpathFirstDirection = currentDirection
                }

                let nextDirection: SIMD3<Float>? = {
                    if i + 1 < elements.count {
                        switch elements[i + 1] {
                        case .line(let nextTo):
                            return nextTo - to
                        case .quadCurve(let nextTo, let control):
                            let firstPoint = subdivideQuadCurve(from: to, to: nextTo, control: control, segments: 20).first ?? nextTo
                            return firstPoint - to
                        case .curve(let nextTo, let control1, let control2):
                            let firstPoint = subdivideCubicCurve(from: to, to: nextTo, control1: control1, control2: control2, segments: 20).first ?? nextTo
                            return firstPoint - to
                        case .closeSubpath:
                            if let start = subpathStart, start != to {
                                return start - to
                            }
                        default:
                            break
                        }
                    }
                    return nil
                }()

                if previousDirection == nil && style.lineCap != .butt {
                    let capVertices = generateEndCap(at: from, from: to, color: color, lineWidth: lineWidth, capStyle: style.lineCap, isStartCap: true)
                    vertices.append(contentsOf: capVertices)
                }

                let lineVertices = generateLineQuad(from: from, to: to, color: color, lineWidth: lineWidth)
                vertices.append(contentsOf: lineVertices)

                if let prevDir = previousDirection, nextDirection != nil {
                    let joinVertices = generateLineJoin(at: from, previousDirection: prevDir, nextDirection: currentDirection, color: color, lineWidth: lineWidth, joinStyle: style.lineJoin, miterLimit: Float(style.miterLimit))
                    vertices.append(contentsOf: joinVertices)
                }

                if let nextDir = nextDirection {
                    let joinVertices = generateLineJoin(at: to, previousDirection: currentDirection, nextDirection: nextDir, color: color, lineWidth: lineWidth, joinStyle: style.lineJoin, miterLimit: Float(style.miterLimit))
                    vertices.append(contentsOf: joinVertices)
                }

                previousDirection = currentDirection
                currentPoint = to

            case .quadCurve(let to, let control):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }

                let curvePoints = subdivideQuadCurve(from: from, to: to, control: control)

                if subpathFirstDirection == nil, let firstPoint = curvePoints.first {
                    subpathFirstDirection = firstPoint - from
                }

                if previousDirection == nil && style.lineCap != .butt {
                    let firstPoint = curvePoints.first ?? to
                    let capVertices = generateEndCap(at: from, from: firstPoint, color: color, lineWidth: lineWidth, capStyle: style.lineCap, isStartCap: true)
                    vertices.append(contentsOf: capVertices)
                }

                var segmentStart = from
                for segmentEnd in curvePoints {
                    let segmentDirection = segmentEnd - segmentStart
                    let lineVertices = generateLineQuad(from: segmentStart, to: segmentEnd, color: color, lineWidth: lineWidth)
                    vertices.append(contentsOf: lineVertices)

                    if let prevDir = previousDirection {
                        let joinVertices = generateLineJoin(at: segmentStart, previousDirection: prevDir, nextDirection: segmentDirection, color: color, lineWidth: lineWidth, joinStyle: style.lineJoin, miterLimit: Float(style.miterLimit))
                        vertices.append(contentsOf: joinVertices)
                    }

                    previousDirection = segmentDirection
                    segmentStart = segmentEnd
                }

                currentPoint = to

            case .curve(let to, let control1, let control2):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }

                let curvePoints = subdivideCubicCurve(from: from, to: to, control1: control1, control2: control2)

                if subpathFirstDirection == nil, let firstPoint = curvePoints.first {
                    subpathFirstDirection = firstPoint - from
                }

                if previousDirection == nil && style.lineCap != .butt {
                    let firstPoint = curvePoints.first ?? to
                    let capVertices = generateEndCap(at: from, from: firstPoint, color: color, lineWidth: lineWidth, capStyle: style.lineCap, isStartCap: true)
                    vertices.append(contentsOf: capVertices)
                }

                var segmentStart = from
                for segmentEnd in curvePoints {
                    let segmentDirection = segmentEnd - segmentStart
                    let lineVertices = generateLineQuad(from: segmentStart, to: segmentEnd, color: color, lineWidth: lineWidth)
                    vertices.append(contentsOf: lineVertices)

                    if let prevDir = previousDirection {
                        let joinVertices = generateLineJoin(at: segmentStart, previousDirection: prevDir, nextDirection: segmentDirection, color: color, lineWidth: lineWidth, joinStyle: style.lineJoin, miterLimit: Float(style.miterLimit))
                        vertices.append(contentsOf: joinVertices)
                    }

                    previousDirection = segmentDirection
                    segmentStart = segmentEnd
                }

                currentPoint = to

            case .closeSubpath:
                if let from = currentPoint, let start = subpathStart, from != start, let prevDir = previousDirection, let firstDir = subpathFirstDirection {
                    let closingDirection = start - from

                    let joinVertices = generateLineJoin(at: from, previousDirection: prevDir, nextDirection: closingDirection, color: color, lineWidth: lineWidth, joinStyle: style.lineJoin, miterLimit: Float(style.miterLimit))
                    vertices.append(contentsOf: joinVertices)

                    let lineVertices = generateLineQuad(from: from, to: start, color: color, lineWidth: lineWidth)
                    vertices.append(contentsOf: lineVertices)

                    let closingJoinVertices = generateLineJoin(at: start, previousDirection: closingDirection, nextDirection: firstDir, color: color, lineWidth: lineWidth, joinStyle: style.lineJoin, miterLimit: Float(style.miterLimit))
                    vertices.append(contentsOf: closingJoinVertices)
                }
                currentPoint = nil
                subpathStart = nil
                subpathFirstDirection = nil
                previousDirection = nil
            }

            i += 1
        }

        if let prev = previousDirection, let current = currentPoint, style.lineCap != .butt {
            let prevPoint = current - prev
            let capVertices = generateEndCap(at: current, from: prevPoint, color: color, lineWidth: lineWidth, capStyle: style.lineCap, isStartCap: false)
            vertices.append(contentsOf: capVertices)
        }

        return vertices
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

    private func generateLineQuad(from: SIMD3<Float>, to: SIMD3<Float>, color: SIMD4<Float>, lineWidth: Float) -> [Vertex] {
        let fromClip = viewProjection * SIMD4<Float>(from, 1.0)
        let toClip = viewProjection * SIMD4<Float>(to, 1.0)

        guard abs(fromClip.w) > 1e-6 && abs(toClip.w) > 1e-6 else {
            fatalError("Degenerate clip space coordinates (w too close to zero)")
        }

        let fromNDC = fromClip.xyz / fromClip.w
        let toNDC = toClip.xyz / toClip.w

        let fromScreen = SIMD2<Float>((fromNDC.x * 0.5 + 0.5) * viewport.x, (fromNDC.y * 0.5 + 0.5) * viewport.y)
        let toScreen = SIMD2<Float>((toNDC.x * 0.5 + 0.5) * viewport.x, (toNDC.y * 0.5 + 0.5) * viewport.y)

        let direction = toScreen - fromScreen
        let length = simd.length(direction)

        guard length > 1e-6 else {
            fatalError("Zero-length line segment")
        }

        let normalizedDir = direction / length
        let perpendicular = SIMD2<Float>(-normalizedDir.y, normalizedDir.x)
        let offset = perpendicular * (lineWidth * 0.5)

        let p0Screen = fromScreen - offset
        let p1Screen = fromScreen + offset
        let p2Screen = toScreen + offset
        let p3Screen = toScreen - offset

        let p0Clip = screenToClip(p0Screen, depth: fromNDC.z, w: fromClip.w)
        let p1Clip = screenToClip(p1Screen, depth: fromNDC.z, w: fromClip.w)
        let p2Clip = screenToClip(p2Screen, depth: toNDC.z, w: toClip.w)
        let p3Clip = screenToClip(p3Screen, depth: toNDC.z, w: toClip.w)

        return [
            Vertex(position: p0Clip, color: color),
            Vertex(position: p1Clip, color: color),
            Vertex(position: p2Clip, color: color),
            Vertex(position: p0Clip, color: color),
            Vertex(position: p2Clip, color: color),
            Vertex(position: p3Clip, color: color)
        ]
    }

    private func screenToClip(_ screenPos: SIMD2<Float>, depth: Float, w: Float) -> SIMD3<Float> {
        let ndcX = (screenPos.x / viewport.x) * 2.0 - 1.0
        let ndcY = (screenPos.y / viewport.y) * 2.0 - 1.0
        return SIMD3<Float>(ndcX, ndcY, depth)
    }

    private func generateEndCap(at point: SIMD3<Float>, from previousPoint: SIMD3<Float>, color: SIMD4<Float>, lineWidth: Float, capStyle: CGLineCap, isStartCap: Bool = false) -> [Vertex] {
        let pointClip = viewProjection * SIMD4<Float>(point, 1.0)
        let prevClip = viewProjection * SIMD4<Float>(previousPoint, 1.0)

        guard abs(pointClip.w) > 1e-6 && abs(prevClip.w) > 1e-6 else {
            return []
        }

        let pointNDC = pointClip.xyz / pointClip.w
        let prevNDC = prevClip.xyz / prevClip.w

        let pointScreen = SIMD2<Float>((pointNDC.x * 0.5 + 0.5) * viewport.x, (pointNDC.y * 0.5 + 0.5) * viewport.y)
        let prevScreen = SIMD2<Float>((prevNDC.x * 0.5 + 0.5) * viewport.x, (prevNDC.y * 0.5 + 0.5) * viewport.y)

        let direction = pointScreen - prevScreen
        let length = simd.length(direction)
        guard length > 1e-6 else { return [] }

        let normalizedDir = direction / length
        let perpendicular = SIMD2<Float>(-normalizedDir.y, normalizedDir.x)
        let radius = lineWidth * 0.5

        switch capStyle {
        case .butt:
            return []

        case .square:
            let offset = perpendicular * radius
            let ext = normalizedDir * radius
            let p0Screen = pointScreen - offset + ext
            let p1Screen = pointScreen + offset + ext
            let p2Screen = pointScreen + offset
            let p3Screen = pointScreen - offset

            let p0 = screenToClip(p0Screen, depth: pointNDC.z, w: pointClip.w)
            let p1 = screenToClip(p1Screen, depth: pointNDC.z, w: pointClip.w)
            let p2 = screenToClip(p2Screen, depth: pointNDC.z, w: pointClip.w)
            let p3 = screenToClip(p3Screen, depth: pointNDC.z, w: pointClip.w)

            return [
                Vertex(position: p0, color: color),
                Vertex(position: p1, color: color),
                Vertex(position: p2, color: color),
                Vertex(position: p0, color: color),
                Vertex(position: p2, color: color),
                Vertex(position: p3, color: color)
            ]

        case .round:
            let segments = segmentCount(for: radius)
            var vertices: [Vertex] = []

            let perpAngle = atan2(perpendicular.y, perpendicular.x)
            let startAngle = perpAngle + Float.pi

            for i in 0..<segments {
                let t1 = Float(i) / Float(segments)
                let t2 = Float(i + 1) / Float(segments)
                let angle1 = startAngle + Float.pi * t1
                let angle2 = startAngle + Float.pi * t2

                let p0Screen = pointScreen
                let p1Screen = pointScreen + SIMD2<Float>(cos(angle1), sin(angle1)) * radius
                let p2Screen = pointScreen + SIMD2<Float>(cos(angle2), sin(angle2)) * radius

                let p0 = screenToClip(p0Screen, depth: pointNDC.z, w: pointClip.w)
                let p1 = screenToClip(p1Screen, depth: pointNDC.z, w: pointClip.w)
                let p2 = screenToClip(p2Screen, depth: pointNDC.z, w: pointClip.w)

                vertices.append(Vertex(position: p0, color: color))
                vertices.append(Vertex(position: p1, color: color))
                vertices.append(Vertex(position: p2, color: color))
            }
            return vertices

        @unknown default:
            return []
        }
    }

    private func generateLineJoin(at point: SIMD3<Float>, previousDirection: SIMD3<Float>, nextDirection: SIMD3<Float>, color: SIMD4<Float>, lineWidth: Float, joinStyle: CGLineJoin, miterLimit: Float) -> [Vertex] {
        let pointClip = viewProjection * SIMD4<Float>(point, 1.0)
        guard abs(pointClip.w) > 1e-6 else { return [] }

        let pointNDC = pointClip.xyz / pointClip.w
        let pointScreen = SIMD2<Float>((pointNDC.x * 0.5 + 0.5) * viewport.x, (pointNDC.y * 0.5 + 0.5) * viewport.y)

        let prevPoint = point - previousDirection
        let nextPoint = point + nextDirection

        let prevClip = viewProjection * SIMD4<Float>(prevPoint, 1.0)
        let nextClip = viewProjection * SIMD4<Float>(nextPoint, 1.0)

        guard abs(prevClip.w) > 1e-6 && abs(nextClip.w) > 1e-6 else { return [] }

        let prevNDC = prevClip.xyz / prevClip.w
        let nextNDC = nextClip.xyz / nextClip.w

        let prevScreen = SIMD2<Float>((prevNDC.x * 0.5 + 0.5) * viewport.x, (prevNDC.y * 0.5 + 0.5) * viewport.y)
        let nextScreen = SIMD2<Float>((nextNDC.x * 0.5 + 0.5) * viewport.x, (nextNDC.y * 0.5 + 0.5) * viewport.y)

        // Work purely in 2D screen space
        let prevDir = normalize(pointScreen - prevScreen)
        let nextDir = normalize(nextScreen - pointScreen)

        let radius = lineWidth * 0.5

        // Cross product determines turn direction (positive = left turn, negative = right turn)
        let crossProduct = prevDir.x * nextDir.y - prevDir.y * nextDir.x

        if abs(crossProduct) < 1e-3 {
            return []  // Lines are parallel, no join needed
        }

        // For the OUTSIDE of the turn, we need perpendiculars pointing away from the turn
        // Left turn (cross > 0): rotate prevDir 90° clockwise, nextDir 90° clockwise
        // Right turn (cross < 0): rotate prevDir 90° counter-clockwise, nextDir 90° counter-clockwise
        let prevPerp = crossProduct > 0 ? SIMD2<Float>(prevDir.y, -prevDir.x) : SIMD2<Float>(-prevDir.y, prevDir.x)
        let nextPerp = crossProduct > 0 ? SIMD2<Float>(nextDir.y, -nextDir.x) : SIMD2<Float>(-nextDir.y, nextDir.x)

        switch joinStyle {
        case .miter:
            // Create offset lines parallel to each segment
            let prevOuter = pointScreen + prevPerp * radius
            let nextOuter = pointScreen + nextPerp * radius

            // Find intersection of the two offset lines:
            // Line 1: prevOuter + t * prevDir
            // Line 2: nextOuter + s * nextDir
            // Solve: prevOuter + t * prevDir = nextOuter + s * nextDir

            let denom = prevDir.x * nextDir.y - prevDir.y * nextDir.x
            if abs(denom) < 1e-6 {
                // Lines are parallel, use bevel
                return generateBevelJoin(at: point, pointScreen: pointScreen, pointNDC: pointNDC, pointClip: pointClip, prevPerp: prevPerp, nextPerp: nextPerp, radius: radius, color: color)
            }

            let diff = nextOuter - prevOuter
            let t = (diff.x * nextDir.y - diff.y * nextDir.x) / denom
            let miterPoint = prevOuter + t * prevDir

            // Check miter limit
            let miterDist = distance(miterPoint, pointScreen)
            let miterRatio = miterDist / radius

            if miterRatio > miterLimit {
                return generateBevelJoin(at: point, pointScreen: pointScreen, pointNDC: pointNDC, pointClip: pointClip, prevPerp: prevPerp, nextPerp: nextPerp, radius: radius, color: color)
            }

            let p0 = screenToClip(pointScreen, depth: pointNDC.z, w: pointClip.w)
            let p1 = screenToClip(prevOuter, depth: pointNDC.z, w: pointClip.w)
            let p2 = screenToClip(miterPoint, depth: pointNDC.z, w: pointClip.w)
            let p3 = screenToClip(nextOuter, depth: pointNDC.z, w: pointClip.w)

            return [
                Vertex(position: p0, color: color),
                Vertex(position: p1, color: color),
                Vertex(position: p2, color: color),
                Vertex(position: p0, color: color),
                Vertex(position: p2, color: color),
                Vertex(position: p3, color: color)
            ]

        case .bevel:
            return generateBevelJoin(at: point, pointScreen: pointScreen, pointNDC: pointNDC, pointClip: pointClip, prevPerp: prevPerp, nextPerp: nextPerp, radius: radius, color: color)

        case .round:
            var vertices: [Vertex] = []
            let segments = segmentCount(for: radius)

            let startAngle = atan2(prevPerp.y, prevPerp.x)
            let endAngle = atan2(nextPerp.y, nextPerp.x)

            var angleDelta = endAngle - startAngle
            if crossProduct > 0 {
                if angleDelta < 0 { angleDelta += 2 * Float.pi }
            } else {
                if angleDelta > 0 { angleDelta -= 2 * Float.pi }
            }

            for i in 0..<segments {
                let t1 = Float(i) / Float(segments)
                let t2 = Float(i + 1) / Float(segments)
                let angle1 = startAngle + angleDelta * t1
                let angle2 = startAngle + angleDelta * t2

                let p0Screen = pointScreen
                let p1Screen = pointScreen + SIMD2<Float>(cos(angle1), sin(angle1)) * radius
                let p2Screen = pointScreen + SIMD2<Float>(cos(angle2), sin(angle2)) * radius

                let p0 = screenToClip(p0Screen, depth: pointNDC.z, w: pointClip.w)
                let p1 = screenToClip(p1Screen, depth: pointNDC.z, w: pointClip.w)
                let p2 = screenToClip(p2Screen, depth: pointNDC.z, w: pointClip.w)

                vertices.append(Vertex(position: p0, color: color))
                vertices.append(Vertex(position: p1, color: color))
                vertices.append(Vertex(position: p2, color: color))
            }

            return vertices

        @unknown default:
            return []
        }
    }

    private func generateBevelJoin(at point: SIMD3<Float>, pointScreen: SIMD2<Float>, pointNDC: SIMD3<Float>, pointClip: SIMD4<Float>, prevPerp: SIMD2<Float>, nextPerp: SIMD2<Float>, radius: Float, color: SIMD4<Float>) -> [Vertex] {
        let prevOuter = pointScreen + prevPerp * radius
        let nextOuter = pointScreen + nextPerp * radius

        let p0 = screenToClip(pointScreen, depth: pointNDC.z, w: pointClip.w)
        let p1 = screenToClip(prevOuter, depth: pointNDC.z, w: pointClip.w)
        let p2 = screenToClip(nextOuter, depth: pointNDC.z, w: pointClip.w)

        return [
            Vertex(position: p0, color: color),
            Vertex(position: p1, color: color),
            Vertex(position: p2, color: color)
        ]
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
            case .quadCurve(let to, let control):
                guard let from = currentPoint else {
                    fatalError("Curve command without preceding move command")
                }
                let curvePoints = subdivideQuadCurve(from: from, to: to, control: control)
                points.append(contentsOf: curvePoints)
                currentPoint = to
            case .curve(let to, let control1, let control2):
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
}
