import GeometryLite3D
import simd
import UltraviolenceExampleShaders

class SceneGraph {
    class Node: Identifiable {
        enum Material {
            case blinnPhong(BlinnPhongMaterial)
            case pbr(PBRMaterialNew)
        }

        var id: ObjectIdentifier {
            ObjectIdentifier(self)
        }
        weak var sceneGraph: SceneGraph?
        weak var parent: Node?
        var label: String?
        var children: [Node]
        var transform: float4x4
        var camera: Camera?
        var light: Light?
        var mesh: Mesh?
        var material: Material?

        init(sceneGraph: SceneGraph? = nil, parent: Node? = nil, children: [Node] = [], transform: float4x4 = .identity) {
            self.sceneGraph = sceneGraph
            self.parent = parent
            self.children = children
            self.transform = transform
        }
    }

    var root: Node
    var currentCameraNode: Node?

    init(root: Node) {
        self.root = root
        root.sceneGraph = self
    }
}

struct Camera {
    var projection: any ProjectionProtocol
}

extension SceneGraph {
    func visit(worldTransform initialTransform: float4x4 = .identity, _ visitor: (Node, float4x4) throws -> Void) rethrows {
        func _visitor(_ node: Node, parentTransform: float4x4) throws {
            let worldTransform = parentTransform * node.transform
            try visitor(node, worldTransform)
            for child in node.children {
                try _visitor(child, parentTransform: worldTransform)
            }
        }
        try _visitor(root, parentTransform: initialTransform)
    }
}
