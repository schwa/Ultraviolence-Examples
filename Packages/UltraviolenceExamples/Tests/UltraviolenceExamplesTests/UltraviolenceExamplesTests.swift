import GeometryLite3D
import simd
import Testing
@testable import UltraviolenceExamples

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
