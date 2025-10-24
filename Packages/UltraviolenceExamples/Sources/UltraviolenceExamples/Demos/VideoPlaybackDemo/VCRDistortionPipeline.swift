import Metal
import MetalKit
import Ultraviolence
import UltraviolenceSupport
import UltraviolenceUI

// Parts based on: https://godotshaders.com/shader/vcr-analog-distortions/

struct VCRParameters {
    // Image distortion
    var curvature: Float = 2.0
    var skip: Float = 0.3
    var imageFlicker: Float = 0.2

    // Vignette
    var vignetteFlickerSpeed: Float = 0.5
    var vignetteStrength: Float = 0.8

    // Scanlines
    var smallScanlinesSpeed: Float = 1.0
    var smallScanlinesProximity: Float = 0.5
    var smallScanlinesOpacity: Float = 0.3
    var scanlinesOpacity: Float = 0.4
    var scanlinesSpeed: Float = 0.8
    var scanlineThickness: Float = 0.5
    var scanlinesSpacing: Float = 1.0

    // Time-based effects
    var noiseAmount: Float = 0.5
    var chromaticAberration: Float = 0.7

    init() {
        // This line intentionally left blank.
    }
}

struct VCRDistortionPipeline: Element {
    let inputTexture: MTLTexture
    let outputTexture: MTLTexture
    let noiseTexture: MTLTexture?
    var parameters: VCRParameters
    let frameUniforms: FrameUniforms

    init(inputTexture: MTLTexture, outputTexture: MTLTexture, noiseTexture: MTLTexture? = nil, parameters: VCRParameters = VCRParameters(), frameUniforms: FrameUniforms) throws {
        self.inputTexture = inputTexture
        self.outputTexture = outputTexture
        self.noiseTexture = noiseTexture ?? Self.createDefaultNoiseTexture(device: inputTexture.device)
        self.parameters = parameters
        self.frameUniforms = frameUniforms
    }

    public var body: some Element {
        get throws {
            let shaderBundle = Bundle.ultraviolenceExampleShaders().orFatalError("Failed to load ultraviolence example shaders bundle")
            let shaderLibrary = try ShaderLibrary(bundle: shaderBundle, namespace: "VCRDistortion")

            let width = outputTexture.width
            let height = outputTexture.height
            let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
            let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)

            try ComputePipeline(computeKernel: try shaderLibrary.vcr_distortion) {
                try ComputeDispatch(threadsPerGrid: threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                    .parameter("inputTexture", texture: inputTexture)
                    .parameter("outputTexture", texture: outputTexture)
                    .parameter("noiseTexture", texture: noiseTexture.orFatalError("Noise texture should be initialized"))
                    .parameter("params", value: parameters)
                    .parameter("frameUniforms", value: frameUniforms)
            }
        }
    }

    private static func createDefaultNoiseTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 256,
            height: 256,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        let texture = device.makeTexture(descriptor: descriptor).orFatalError("Failed to create noise texture")
        texture.label = "VCR Noise Texture"

        // Generate random noise
        var noiseData = [UInt8](repeating: 0, count: 256 * 256)
        for i in 0..<noiseData.count {
            noiseData[i] = UInt8.random(in: 0...255)
        }

        texture.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 256, height: 256, depth: 1)),
            mipmapLevel: 0,
            withBytes: noiseData,
            bytesPerRow: 256
        )

        return texture
    }
}
