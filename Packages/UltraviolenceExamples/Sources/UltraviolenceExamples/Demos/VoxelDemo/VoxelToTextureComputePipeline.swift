import GeometryLite3D
import Metal
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceSupport
import UltraviolenceUI

struct VoxelToTextureComputePipeline: Element {
    let projection: PerspectiveProjection
    let aspectRatio: Float
    let cameraMatrix: float4x4
    let voxelTexture: MTLTexture
    let outputTexture: MTLTexture
    let voxelScale: SIMD3<Float>

    var voxelComputeShader: ComputeKernel

    init(projection: any ProjectionProtocol, aspectRatio: Float, cameraMatrix: float4x4, voxelTexture: MTLTexture, outputTexture: MTLTexture, voxelScale: SIMD3<Float>) throws {
        guard let perspectiveProjection = projection as? PerspectiveProjection else {
            throw UltraviolenceError.generic("VoxelToTextureComputePipeline requires a PerspectiveProjection")
        }
        self.projection = perspectiveProjection
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
                if case let .standard(zRange) = projection.depthMode {
                    try ComputeDispatch(
                        threadsPerGrid: outputTexture.size,
                        threadsPerThreadgroup: MTLSize(width: 32, height: 32, depth: 1) // TODO: hard coded
                    )
                    .parameter("voxelTexture", texture: voxelTexture)
                    .parameter("outputTexture", texture: outputTexture)
                    .parameter("projectionMatrix", value: projectionMatrix)
                    .parameter("inverseProjectionMatrix", value: projectionMatrix.inverse)
                    .parameter("near", value: zRange.lowerBound)
                    .parameter("far", value: zRange.upperBound)
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
}
