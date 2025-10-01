import GeometryLite3D
import simd
import XCTest
@testable import UltraviolenceExamples

final class SceneGraphTransformTests: XCTestCase {
    func test_WhenVisitingWorldTransforms_ThenStackedTransformsApplied() {
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

        XCTAssertEqual(worldTransforms[rootNode.id], rootTransform)
        XCTAssertEqual(worldTransforms[childNode.id], rootTransform * childTransform)
        XCTAssertEqual(worldTransforms[grandchildNode.id], rootTransform * childTransform * grandchildTransform)
    }
}

private func XCTAssertEqual(_ matrix: float4x4?, _ expected: float4x4?, accuracy: Float = 1e-5, file: StaticString = #filePath, line: UInt = #line) {
    guard let matrix, let expected else {
        XCTFail("Nil matrices cannot be compared", file: file, line: line)
        return
    }
    for columnIndex in 0..<4 {
        for rowIndex in 0..<4 {
            XCTAssertEqual(matrix[columnIndex][rowIndex], expected[columnIndex][rowIndex], accuracy: accuracy, file: file, line: line)
        }
    }
}
