import GeometryLite3D
import Metal
import MetalKit
import Panels
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceSupport
import UltraviolenceUI

public struct SceneGraphDemoView: View {
    let sceneGraph: SceneGraph

    @State
    private var projection: any ProjectionProtocol = PerspectiveProjection()

    @State
    private var cameraMatrix = simd_float4x4(translation: [0, 2, 5])

    let environmentTexture: MTLTexture

    public init() {
        let device = _MTLCreateSystemDefaultDevice()
        let sceneGraph = SceneGraph.demo(device: device)
        self.init(sceneGraph: sceneGraph)
    }

    internal init(sceneGraph: SceneGraph) {
        self.sceneGraph = sceneGraph

        let device = _MTLCreateSystemDefaultDevice()
        let textureLoader = MTKTextureLoader(device: device)
        let envURL = Bundle.module.url(forResource: "IndoorEnvironmentHDRI013_1K-HDR", withExtension: "exr")!
        environmentTexture = try! textureLoader.newTexture(URL: envURL, options: [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .generateMipmaps: true,
            .SRGB: false
        ])
    }

    public var body: some View {
        WorldView(projection: $projection, cameraMatrix: $cameraMatrix, targetMatrix: .constant(nil)) {
            RenderView { _, drawableSize in
                SceneGraphRenderPass(sceneGraph: sceneGraph, cameraMatrix: cameraMatrix, projectionMatrix: projection.projectionMatrix(for: drawableSize), environmentTexture: environmentTexture)
            }
            .metalDepthStencilPixelFormat(.depth32Float)
            .panel(id: "SceneGraphEditorView", label: "Scene Graph") {
                SceneGraphEditorView(sceneGraph: sceneGraph)
            }
        }
    }
}

struct SceneGraphEditorView: View {
    let sceneGraph: SceneGraph

    @State
    private var selectedNode: SceneGraph.Node.ID?

    var body: some View {
        List([sceneGraph.root], children: \.listChildren, selection: $selectedNode) { node in
            VStack {
                Text("Node: \(node.label)")
                if selectedNode == node.id {
                    LabeledContent("Transform") {
                        Text("\(node.transform)")
                    }
                    LabeledContent("Camera") {
                        Text("\(node.camera != nil ? "Yes" : "No")")
                    }
                    LabeledContent("Light") {
                        Text("\(node.light != nil ? "Yes" : "No")")
                    }
                    LabeledContent("Mesh") {
                        Text("\(node.mesh != nil ? "Yes" : "No")")
                    }
                    LabeledContent("Material") {
                        Text("\(node.material != nil ? "Yes" : "No")")
                    }
                }
            }
        }
    }
}

extension SceneGraph.Node {
    // swiftlint:disable:next discouraged_optional_collection
    var listChildren: [SceneGraph.Node]? {
        children.isEmpty ? nil : children
    }
}
