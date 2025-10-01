import GeometryLite3D
import Metal
import simd
import UltraviolenceExampleShaders

extension SceneGraph {
    static func demo(device: MTLDevice) -> SceneGraph {
        // Create root node
        let rootNode = Node(sceneGraph: nil, parent: nil)

        // Create camera node
        let cameraNode = Node(sceneGraph: nil, parent: rootNode, transform: float4x4(translation: [0, 0, 5]))
        cameraNode.camera = Camera(
            projection: PerspectiveProjection()
        )

        // Create light node
        let lightNode = Node(sceneGraph: nil, parent: rootNode, transform: float4x4(translation: [1, 1, 1]))
        lightNode.light = Light(type: .point, color: [1, 1, 1], intensity: 50.0)

        // Create a grid of shapes: row nodes own lateral offsets, columns apply local transforms
        let rowCount = 4
        let columnCount = 4
        let columnSpacing: Float = 1.5
        let rowSpacing: Float = 1.5

        let shapeFactories: [() -> TrivialMesh] = [
            { TrivialMesh.box() },
            { TrivialMesh.sphere() },
            { TrivialMesh.cone() },
            { TrivialMesh.torus() },
            { TrivialMesh.capsule() },
            { TrivialMesh.octahedron() }
        ]

        var rowNodes: [Node] = []
        let rowOffset = Float(rowCount - 1) / 2
        let columnOffset = Float(columnCount - 1) / 2

        for row in 0..<rowCount {
            let rowTranslation = SIMD3<Float>(0, 0, (Float(row) - rowOffset) * rowSpacing)
            let rowNode = Node(sceneGraph: nil, parent: rootNode, transform: float4x4(translation: rowTranslation))
            rowNode.label = "Row \(row)"

            var cells: [Node] = []
            for column in 0..<columnCount {
                let columnTranslation = SIMD3<Float>((Float(column) - columnOffset) * columnSpacing, 0, 0)
                let cellNode = Node(sceneGraph: nil, parent: rowNode, transform: float4x4(translation: columnTranslation))
                cellNode.label = "Cell \(row),\(column)"

                let shape = shapeFactories[(row * columnCount + column) % shapeFactories.count]()
                cellNode.mesh = Mesh(shape.generateTangents(), device: device)

                if (row + column) % 2 == 0 {
                    cellNode.material = .blinnPhong(
                        BlinnPhongMaterial(
                            ambient: .color([0.1, 0.1, 0.1]),
                            diffuse: .color([0.7, 0.3, 0.4]),
                            specular: .color([1.0, 1.0, 1.0]),
                            shininess: 24.0
                        )
                    )
                }
                else {
                    var material = PBRMaterialNew()
                    material.albedo = .color(SIMD3<Float>(0.3 + 0.2 * Float(row), 0.5, 0.7 - 0.1 * Float(column)))
                    material.metallic = .color(0.2 + 0.1 * Float(row))
                    material.roughness = .color(0.8 - 0.1 * Float(column))
                    cellNode.material = .pbr(material)
                }

                cells.append(cellNode)
            }

            rowNode.children = cells
            rowNodes.append(rowNode)
        }

        // Set up hierarchy
        rootNode.children = [cameraNode, lightNode] + rowNodes

        // Create scene graph
        let sceneGraph = SceneGraph(root: rootNode)
        sceneGraph.currentCameraNode = cameraNode

        // Update scene graph references
        func updateSceneGraphReferences(_ node: Node) {
            node.sceneGraph = sceneGraph
            for child in node.children {
                updateSceneGraphReferences(child)
            }
        }
        updateSceneGraphReferences(rootNode)

        return sceneGraph
    }
}
