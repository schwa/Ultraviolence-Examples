import Metal
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport

struct HitTestShader<Content>: Element where Content: Element {
    var vertexShader: VertexShader
    var fragmentShader: FragmentShader
    var content: Content

    init(@ElementBuilder content: () throws -> Content) throws {
        let device = _MTLCreateSystemDefaultDevice()
        assert(device.argumentBuffersSupport == .tier2)
        let shaderBundle = Bundle.ultraviolenceExampleShaders().orFatalError("Failed to load ultraviolence example shaders bundle")
        let shaderLibrary = try ShaderLibrary(bundle: shaderBundle, namespace: "HitTest")
        vertexShader = try shaderLibrary.vertex_main
        fragmentShader = try shaderLibrary.fragment_main
        self.content = try content()
    }

    public var body: some Element {
        get throws {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
            }
            .renderPipelineDescriptorModifier { descriptor in
                descriptor.colorAttachments[0].pixelFormat = .r32Sint
                descriptor.colorAttachments[1].pixelFormat = .r32Sint
                descriptor.colorAttachments[2].pixelFormat = .r32Sint
                descriptor.colorAttachments[3].pixelFormat = .r32Float
                descriptor.colorAttachments[4].pixelFormat = .rgba32Float
            }
        }
    }
}

extension Element {
    func geometryID(_ id: Int32) -> some Element {
        self.parameter("geometryID", value: id)
    }
}
