import Metal
import Ultraviolence
import UltraviolenceExampleShaders

public struct BlinnPhongShader<Content>: Element where Content: Element {
    var vertexShader: VertexShader
    var fragmentShader: FragmentShader

    var content: Content

    @UVEnvironment(\.device)
    var device

    public init(@ElementBuilder content: () throws -> Content) throws {
        let device = MTLCreateSystemDefaultDevice().orFatalError()
        assert(device.argumentBuffersSupport == .tier2)
        let shaderBundle = Bundle.ultraviolenceExampleShaders().orFatalError()
        let shaderLibrary = try ShaderLibrary(bundle: shaderBundle, namespace: "BlinnPhong")
        vertexShader = try shaderLibrary.vertex_main
        fragmentShader = try shaderLibrary.fragment_main

        self.content = try content()
    }

    public var body: some Element {
        get throws {
            let device = try device.orThrow(.missingEnvironment(\.device))
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
            }
        }
    }
}

