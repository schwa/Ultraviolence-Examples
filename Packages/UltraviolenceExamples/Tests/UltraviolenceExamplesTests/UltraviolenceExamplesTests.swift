import CoreGraphics
import GeometryLite3D
import simd
import Testing
@testable import UltraviolenceExamples

@Suite
struct LineJoinTests {
    @Test("Line joins extend outward at corners")
    func lineJoinsExtendOutward() {
        // Create a simple 90-degree corner: (0,0) -> (1,0) -> (1,1)
        let p0 = SIMD3<Float>(0, 0, 0)
        let p1 = SIMD3<Float>(1, 0, 0)
        let p2 = SIMD3<Float>(1, 1, 0)
        let lineWidth: Float = 40.0
        let radius = lineWidth / 2.0

        let viewProjection = float4x4.identity
        let viewport = SIMD2<Float>(800, 600)
        let generator = GeometryGenerator(viewProjection: viewProjection, viewport: viewport)

        let path = Path3D { path in
            path.move(to: p0)
            path.addLine(to: p1)
            path.addLine(to: p2)
        }

        let color = SIMD4<Float>(0, 1, 0, 1)
        let style = StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .butt, lineJoin: .round)

        let vertices = generator.generateStrokeGeometry(path: path, color: color, style: style)

        #expect(!vertices.isEmpty, "Should generate vertices")

        // Compute bounding box
        var minX: Float = .infinity
        var maxX: Float = -.infinity
        var minY: Float = .infinity
        var maxY: Float = -.infinity

        for vertex in vertices {
            minX = min(minX, vertex.position.x)
            maxX = max(maxX, vertex.position.x)
            minY = min(minY, vertex.position.y)
            maxY = max(maxY, vertex.position.y)
        }

        // For a path going RIGHT then UP, the outside corner extends diagonally DOWN-RIGHT
        // At -45°, the offset is: (radius * cos(-45°), radius * sin(-45°)) = (radius * 0.707, radius * -0.707)
        let diagonalOffset = radius * 0.707
        let expectedCornerX = p1.x + (diagonalOffset / viewport.x) * 2.0
        let expectedCornerY = p1.y - (diagonalOffset / viewport.y) * 2.0

        // Check if any vertex is near the expected diagonal position
        let tolerance: Float = 0.02
        var foundDiagonalVertex = false
        for vertex in vertices {
            let distX = abs(vertex.position.x - expectedCornerX)
            let distY = abs(vertex.position.y - expectedCornerY)
            if distX < tolerance, distY < tolerance {
                foundDiagonalVertex = true
                break
            }
        }

        #expect(foundDiagonalVertex, "Should find a vertex extending diagonally outward from the corner (expected near \(expectedCornerX), \(expectedCornerY))")
    }
}

@Suite
struct EndCapBoundingBoxTests {
    @Test("Round caps extend outward beyond line endpoints")
    func roundCapsExtendOutward() {
        let lineStart = SIMD3<Float>(-3, 0, 0)
        let lineEnd = SIMD3<Float>(3, 0, 0)
        let lineWidth: Float = 40.0
        let radius = lineWidth / 2.0

        let viewProjection = float4x4.identity
        let viewport = SIMD2<Float>(800, 600)
        let generator = GeometryGenerator(viewProjection: viewProjection, viewport: viewport)

        let path = Path3D { path in
            path.move(to: lineStart)
            path.addLine(to: lineEnd)
        }

        let color = SIMD4<Float>(1, 0.5, 0, 1)
        let style = StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: .round)

        let vertices = generator.generateStrokeGeometry(path: path, color: color, style: style)

        #expect(!vertices.isEmpty, "Should generate vertices")

        // Compute bounding box
        var minX: Float = .infinity
        var maxX: Float = -.infinity
        var minY: Float = .infinity
        var maxY: Float = -.infinity

        for vertex in vertices {
            minX = min(minX, vertex.position.x)
            maxX = max(maxX, vertex.position.x)
            minY = min(minY, vertex.position.y)
            maxY = max(maxY, vertex.position.y)
        }

        // Caps extend by radius in screen pixels, which translates to NDC based on viewport
        let radiusNDC_X = (radius / viewport.x) * 2.0
        let radiusNDC_Y = (radius / viewport.y) * 2.0

        // For round caps, the bounding box should extend by radius (in NDC) in all directions
        let tolerance: Float = 0.01
        #expect(minX <= lineStart.x - radiusNDC_X + tolerance, "Left edge should extend beyond line start by radius")
        #expect(maxX >= lineEnd.x + radiusNDC_X - tolerance, "Right edge should extend beyond line end by radius")
        #expect(minY <= lineStart.y - radiusNDC_Y + tolerance, "Bottom should extend by radius")
        #expect(maxY >= lineStart.y + radiusNDC_Y - tolerance, "Top should extend by radius")
    }
}

@Suite
struct SceneGraphTransformTests {
    @Test("World transforms accumulate parent hierarchies")
    func whenVisitingWorldTransforms_thenStackedTransformsApplied() {
        let rootTransform = float4x4(translation: [1, 0, 0])
        let childTransform = float4x4(translation: [0, 2, 0])
        let grandchildTransform = float4x4(scale: [0.5, 0.5, 0.5]) * float4x4(translation: [0, 0, 3])

        let rootNode = SceneGraph.Node(sceneGraph: nil, parent: nil, children: [], transform: rootTransform)
        let childNode = SceneGraph.Node(sceneGraph: nil, parent: rootNode, children: [], transform: childTransform)
        let grandchildNode = SceneGraph.Node(sceneGraph: nil, parent: childNode, children: [], transform: grandchildTransform)

        childNode.children = [grandchildNode]
        rootNode.children = [childNode]

        let graph = SceneGraph(root: rootNode)

        var worldTransforms: [SceneGraph.Node.ID: float4x4] = [:]
        graph.visit(worldTransform: .identity) { node, worldTransform in
            worldTransforms[node.id] = worldTransform
        }

        let tolerance: Float = 1e-5
        expectWorldTransform(worldTransforms, for: rootNode, equals: rootTransform, tolerance: tolerance, context: "root node")
        expectWorldTransform(worldTransforms, for: childNode, equals: rootTransform * childTransform, tolerance: tolerance, context: "child node")
        expectWorldTransform(
            worldTransforms,
            for: grandchildNode,
            equals: rootTransform * childTransform * grandchildTransform,
            tolerance: tolerance,
            context: "grandchild node"
        )
    }
}

private func expectWorldTransform(
    _ worldTransforms: [SceneGraph.Node.ID: float4x4],
    for node: SceneGraph.Node,
    equals expected: float4x4,
    tolerance: Float,
    context: String
) {
    guard let matrix = worldTransforms[node.id] else {
        Issue.record("Missing world transform for \(context)")
        return
    }
    #expect(simd_almost_equal_elements(matrix, expected, tolerance), "Unexpected world transform for \(context)")
}
