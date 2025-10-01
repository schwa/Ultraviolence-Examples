import Metal
import simd
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport

// TODO: Lighing is static once generated.

struct SceneGraphRenderPass: Element {
    var sceneGraph: SceneGraph
    var cameraMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
    var lighting: Lighting
    var environmentTexture: MTLTexture
    private let nodesWithWorldTransforms: [(node: SceneGraph.Node, worldTransform: float4x4)]

    init(sceneGraph: SceneGraph, cameraMatrix: simd_float4x4, projectionMatrix: simd_float4x4, environmentTexture: MTLTexture) {
        self.sceneGraph = sceneGraph
        self.cameraMatrix = cameraMatrix
        self.projectionMatrix = projectionMatrix

        var worldTransforms: [(SceneGraph.Node, float4x4)] = []
        sceneGraph.visit(worldTransform: .identity) { node, worldTransform in
            worldTransforms.append((node, worldTransform))
        }
        self.nodesWithWorldTransforms = worldTransforms

        // TODO: We are generating this every frame! [FILE ME]
        let lights = worldTransforms.compactMap { node, worldTransform -> (SIMD3<Float>, Light)? in
            guard let light = node.light else {
                return nil
            }
            return (worldTransform.translation, light)
        }
        if lights.isEmpty {
            self.lighting = (try? Lighting.demo()).orFatalError("Failed to load demo lighting")
        }
        else {
            self.lighting = (try? Lighting(ambientLightColor: [1, 1, 1], lights: lights))
                .orFatalError("Failed to create scene graph lighting")
        }
        self.environmentTexture = environmentTexture
    }

    var body: some Element {
        get throws {
            try RenderPass {
                try GridShader(projectionMatrix: projectionMatrix, cameraMatrix: cameraMatrix)
                try blinnPhong
                try pbr
            }
        }
    }

    @ElementBuilder
    var blinnPhong: some Element {
        get throws {
            let meshNodes = nodesWithWorldTransforms.filter { $0.node.mesh != nil }
            let blinnPhongNodes = meshNodes.filter { entry in
                if case .blinnPhong = entry.node.material {
                    return true
                }
                return false
            }
            try BlinnPhongShader {
                try ForEach(Array(blinnPhongNodes.enumerated()), id: \.offset) { _, entry in
                    let node = entry.node
                    let worldTransform = entry.worldTransform
                    if let mesh = node.mesh, case let .blinnPhong(material) = node.material {
                        try Draw { encoder in
                            encoder.draw(mesh: mesh)
                        }
                        .blinnPhongMaterial(material)
                        .transforms(.init(modelMatrix: worldTransform, cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix))
                    }
                }
                .lighting(lighting)
            }
            .vertexDescriptor(.default)
            .depthCompare(function: .less, enabled: true)
        }
    }

    @ElementBuilder
    var pbr: some Element {
        get throws {
            let meshNodes = nodesWithWorldTransforms.filter { $0.node.mesh != nil }
            let pbrNodes = meshNodes.filter { entry in
                if case .pbr = entry.node.material {
                    return true
                }
                return false
            }
            try PBRShader {
                try ForEach(Array(pbrNodes.enumerated()), id: \.offset) { _, entry in
                    let node = entry.node
                    let worldTransform = entry.worldTransform
                    if let mesh = node.mesh, case let .pbr(material) = node.material {
                        Draw { encoder in
                            encoder.draw(mesh: mesh)
                        }
                        .pbrMaterial(material)
                        .pbrUniforms(modelTransform: worldTransform, cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix)
                    }
                }
                .pbrEnvironment(environmentTexture)
                .lighting(lighting)
            }
            .vertexDescriptor(.default)
            .depthCompare(function: .less, enabled: true)
        }
    }
}

extension SceneGraph {
    func dump() {
        func _dump(_ node: Node, level: Int) {
            let indent = String(repeating: "  ", count: level)
            print("\(indent)- Node(name: \(String(describing: node.label)), mesh: \(node.mesh != nil ? "yes" : "no"), material: \(node.material != nil ? "\(type(of: node.material!))" : "no"))")
            for child in node.children {
                _dump(child, level: level + 1)
            }
        }
        _dump(root, level: 0)
    }
}

extension VertexDescriptor {
    static var `default`: Self {
        .init(attributes: [
            .init(semantic: .position, format: .float3, offset: 0, bufferIndex: 0),
            .init(semantic: .normal, format: .float3, offset: 0, bufferIndex: 0),
            .init(semantic: .texcoord, format: .float2, offset: 0, bufferIndex: 0),
            .init(semantic: .tangent, format: .float3, offset: 0, bufferIndex: 0),
            .init(semantic: .bitangent, format: .float3, offset: 0, bufferIndex: 0)
        ], layouts: [
            .init(bufferIndex: 0)
        ])
        .normalizingOffsets()
        .normalizingStrides()
    }
}

extension Element {
    func vertexDescriptor(_ vertexDescriptor: VertexDescriptor) -> some Element {
        let mtlVertexDescriptor = MTLVertexDescriptor(vertexDescriptor)
        return self.vertexDescriptor(mtlVertexDescriptor)
    }
}
