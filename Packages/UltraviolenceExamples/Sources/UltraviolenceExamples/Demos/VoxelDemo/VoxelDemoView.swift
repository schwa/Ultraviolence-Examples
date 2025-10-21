import GeometryLite3D
import Interaction3D
import Metal
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceSupport
import UltraviolenceUI
import UniformTypeIdentifiers

public struct VoxelDemoView: View {
    @State
    private var projection: any ProjectionProtocol = PerspectiveProjection()

    @State
    private var cameraMatrix: float4x4 = .identity

    @State
    private var voxelTexture: MTLTexture?

    @State
    private var colorTexture: MTLTexture?

    @State
    private var voxelSize = MTLSize(width: 4, height: 4, depth: 4)

    @State
    private var voxelScale: SIMD3<Float> = [1, 1, 1]

    @State
    private var magicaVoxelURL: URL?

    public init() {
        // This line intentionally left blank.
    }

    public var body: some View {
        WorldView(projection: $projection, cameraMatrix: $cameraMatrix) {
            RenderView { _, drawableSize in
                try ComputePass(label: "VoxelToTexture") {
                    if let voxelTexture, let colorTexture {
                        try VoxelToTextureComputePipeline(projection: projection, aspectRatio: Float(drawableSize.width / drawableSize.height), cameraMatrix: cameraMatrix, voxelTexture: voxelTexture, outputTexture: colorTexture, voxelScale: voxelScale)
                    }
                }
                try RenderPass {
                    if let colorTexture {
                        try TextureBillboardPipeline(specifier: .texture2D(colorTexture))
                    }
                }
                .onChange(of: drawableSize, initial: true) { _, _ in
                    colorTexture = makeRenderTexture(size: MTLSize(drawableSize))
                }
            }
        }
        .onChange(of: voxelSize, initial: true) {
            generateDefaultVoxelTexture()
        }
        .onChange(of: magicaVoxelURL, initial: true) {
            guard let magicaVoxelURL else {
                generateDefaultVoxelTexture()
                return
            }
            do {
                let model = try MagicaVoxelModel(contentsOf: magicaVoxelURL)
                print(model.size)

                let texture = try model.makeTexture()
                voxelTexture = texture
                voxelScale = SIMD3<Float>(0.01, 0.01, 0.01)
            }
            catch {
                assertionFailure("Failed to load MagicaVoxel model: \(error)")
            }
        }

        .overlay(alignment: .bottom) {
            Form {
                Text("Voxel Size: \(voxelSize.width) x \(voxelSize.height) x \(voxelSize.depth)")

                let memory = Measurement(value: Double(voxelSize.width * voxelSize.height * voxelSize.depth * MemoryLayout<SIMD3<Float>>.size), unit: UnitInformationStorage.bytes)

                Text("# voxels: \(voxelSize.width * voxelSize.height * voxelSize.depth) (\(memory.formatted(.byteCount(style: .memory))) )")
                Text("Voxel Scale: \(voxelScale.x) x \(voxelScale.y) x \(voxelScale.z)")
                HStack {
                    Button("/2") {
                        voxelSize = MTLSize(width: voxelSize.width / 2, height: voxelSize.height / 2, depth: voxelSize.depth / 2)
                        voxelScale *= 2
                    }
                    Button("x2") {
                        voxelSize = MTLSize(width: voxelSize.width * 2, height: voxelSize.height * 2, depth: voxelSize.depth * 2)
                        voxelScale *= 0.5
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .toolbar {
            SuperImportWidget(url: $magicaVoxelURL, identifier: "magica-voxel", allowedContentTypes: [.magicaVoxel])
        }
    }

    func generateDefaultVoxelTexture() {
        let device = _MTLCreateSystemDefaultDevice()
        do {
            print("Generating voxel texture of size \(voxelSize)")
            voxelTexture = try makeSphereVoxelTexture(device: device, size: voxelSize)
            voxelScale = SIMD3<Float>(1, 1, 1)
        }
        catch {
            assertionFailure("Failed to create voxel texture: \(error)")
        }
    }

    func makeRenderTexture(size: MTLSize) -> MTLTexture {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size.width, height: size.height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        let device = _MTLCreateSystemDefaultDevice()
        let texture = device.makeTexture(descriptor: textureDescriptor).orFatalError("Failed to create render texture")
        texture.label = "Color Texture"
        return texture
    }

    func makeSphereVoxelTexture(device: MTLDevice?, size: MTLSize) throws -> MTLTexture {
        guard let device else {
            throw UltraviolenceError.resourceCreationFailure("Metal device unavailable.")
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = size.width
        descriptor.height = size.height
        descriptor.depth = size.depth
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw UltraviolenceError.resourceCreationFailure("Failed to create voxel texture.")
        }
        texture.label = "Voxel Texture"

        let shaderBundle = Bundle.ultraviolenceExampleShaders().orFatalError("Failed to load shader bundle")
        let shaderLibrary = try ShaderLibrary(bundle: shaderBundle, namespace: "VoxelShaders")
        let kernel: ComputeKernel = try shaderLibrary.voxel_generateSphere

        let threadsPerThreadgroup = MTLSize(
            width: max(1, min(4, size.width)),
            height: max(1, min(4, size.height)),
            depth: max(1, min(4, size.depth))
        )

        let computePass = try ComputePass(label: "GenerateVoxelSphere") {
            try ComputePipeline(computeKernel: kernel) {
                try ComputeDispatch(
                    threadsPerGrid: size,
                    threadsPerThreadgroup: threadsPerThreadgroup
                )
                .parameter("voxelTexture", texture: texture)
            }
        }

        try computePass.run()

        return texture
    }
}

extension UTType {
    static let magicaVoxel = UTType(filenameExtension: "vox").orFatalError("Failed to create magicaVoxel UTType")
}

extension MagicaVoxelModel {
    func makeTexture() throws -> MTLTexture {
        let device = _MTLCreateSystemDefaultDevice()
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = Int(size.x)
        descriptor.height = Int(size.y)
        descriptor.depth = Int(size.z)
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw UltraviolenceError.resourceCreationFailure("Failed to create voxel texture.")
        }
        texture.label = "MagicaVoxel Texture"

        for voxel in voxels {
            let position = voxel.0
            let color = colors[Int(voxel.1)]
            let colorData: [UInt8] = [color.x, color.y, color.z, 255]
            texture.replace(region: MTLRegionMake3D(Int(position.x), Int(position.y), Int(position.z), 1, 1, 1), mipmapLevel: 0, slice: 0, withBytes: colorData, bytesPerRow: 4, bytesPerImage: 4)
        }

        return texture
    }
}
