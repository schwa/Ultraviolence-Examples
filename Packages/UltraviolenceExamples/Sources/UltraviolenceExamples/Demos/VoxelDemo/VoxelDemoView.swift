import GeometryLite3D
import Metal
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceSupport
import UltraviolenceUI

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
            let device = _MTLCreateSystemDefaultDevice()
            do {
                print("Generating voxel texture of size \(voxelSize)")
                voxelTexture = try makeSphereVoxelTexture(device: device, size: voxelSize)
            }
            catch {
                assertionFailure("Failed to create voxel texture: \(error)")
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
    }

    func makeRenderTexture(size: MTLSize) -> MTLTexture {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size.width, height: size.height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        let device = _MTLCreateSystemDefaultDevice()
        let texture = device.makeTexture(descriptor: textureDescriptor).orFatalError("TODO")
        texture.label = "Color Texture"
        return texture
    }
}

@MainActor
private func makeSphereVoxelTexture(device: MTLDevice?, size: MTLSize) throws -> MTLTexture {
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

extension MTLSize {
    init(_ size: CGSize) {
        self.init(width: Int(size.width), height: Int(size.height), depth: 1)
    }
}

struct VoxelToTextureComputePipeline: Element {
    let projection: OldPerspectiveProjection
    let aspectRatio: Float
    let cameraMatrix: float4x4
    let voxelTexture: MTLTexture
    let outputTexture: MTLTexture
    let voxelScale: SIMD3<Float>

    var voxelComputeShader: ComputeKernel

    init(projection: any ProjectionProtocol, aspectRatio: Float, cameraMatrix: float4x4, voxelTexture: MTLTexture, outputTexture: MTLTexture, voxelScale: SIMD3<Float>) throws {
        self.projection = projection as! OldPerspectiveProjection // TODO: as! bad!
        self.aspectRatio = aspectRatio
        self.cameraMatrix = cameraMatrix
        self.voxelTexture = voxelTexture
        self.outputTexture = outputTexture
        self.voxelScale = voxelScale
        let bundle = Bundle.ultraviolenceExampleShaders().orFatalError("Failed to load shader bundle")
        let shaderLibrary = try ShaderLibrary(bundle: bundle, namespace: "VoxelShaders")
        self.voxelComputeShader = try shaderLibrary.voxel_main
    }

    var body: some Element {
        get throws {
            try ComputePipeline(computeKernel: voxelComputeShader) {
                let viewMatrix = cameraMatrix.inverse
                let projectionMatrix = projection.projectionMatrix(aspectRatio: aspectRatio)
                let viewProj = projectionMatrix * viewMatrix
                let invViewProj = simd_inverse(viewProj)
                let cameraPosition = cameraMatrix.columns.3.xyz

                try ComputeDispatch(
                    threadsPerGrid: outputTexture.size,
                    threadsPerThreadgroup: MTLSize(width: 32, height: 32, depth: 1) // TODO: hard coded
                )
                .parameter("voxelTexture", texture: voxelTexture)
                .parameter("outputTexture", texture: outputTexture)
                .parameter("projectionMatrix", value: projectionMatrix)
                .parameter("inverseProjectionMatrix", value: projectionMatrix.inverse)
                .parameter("near", value: projection.zClip.lowerBound)
                .parameter("far", value: projection.zClip.upperBound)
                .parameter("cameraMatrix", value: cameraMatrix)
                .parameter("viewMatrix", value: viewMatrix)
                .parameter("invViewProj", value: invViewProj)
                .parameter("cameraPosition", value: cameraPosition)
                .parameter("voxelModelMatrix", value: float4x4.identity)
                .parameter("voxelScale", value: voxelScale)
            }
        }
    }
}

extension MTLTexture {
    var size: MTLSize {
        MTLSize(width: width, height: height, depth: depth)
    }
}

extension MTLSize: @retroactive Equatable {
    public static func == (lhs: MTLSize, rhs: MTLSize) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.depth == rhs.depth
    }
}
