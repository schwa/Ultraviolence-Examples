#if os(iOS)
import ARKit
import CoreVideo
import GeometryLite3D
import Metal
import MetalKit
import Observation
import SwiftUI
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport
import UltraviolenceUI

public struct ARKitDemoView: View {
    @State
    private var viewModel = ARKitDemoViewModel()

    @State
    private var showMeshes = true

    @State
    private var showPlanes = true

    @State
    private var limitAnchors = false

    let teapot: MTKMesh
    let environmentTexture: MTLTexture

    public init() {
        teapot = (try? MTKMesh.teapot(options: [.generateTangentBasis, .generateTextureCoordinatesIfMissing, .useSimpleTextureCoordinates]))
            .orFatalError("Failed to load AR teapot mesh")
        let device = _MTLCreateSystemDefaultDevice()
        let textureLoader = MTKTextureLoader(device: device)
        let envURL = Bundle.module.url(forResource: "IndoorEnvironmentHDRI013_1K-HDR", withExtension: "exr").orFatalError("Missing environment texture resource")
        environmentTexture = (try? textureLoader.newTexture(URL: envURL, options: [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue,
            .generateMipmaps: true,
            .SRGB: false
        ])).orFatalError("Failed to load AR environment texture")
    }

    public var body: some View {
        ZStack {
            RenderView { _, drawableSize in
                try RenderPass {
                    if let currentFrame = viewModel.currentFrame, let textureY = viewModel.currentTextureY, let textureCbCr = viewModel.currentTextureCbCr {
                        let interfaceOrientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .portrait
                        let viewMatrix = currentFrame.camera.viewMatrix(for: interfaceOrientation)
                        let projectionMatrix = currentFrame.camera.projectionMatrix(for: interfaceOrientation, viewportSize: drawableSize, zNear: 0.001, zFar: 1_000)
                        let viewProjectionMatrix = projectionMatrix * viewMatrix

                        let displayTransform = currentFrame.displayTransform(for: interfaceOrientation, viewportSize: drawableSize).inverted()
                        let texCoords: [CGPoint] = [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint.zero, CGPoint(x: 1, y: 0)]
                        let transformedTexCoords = texCoords.map { coord in
                            let transformed = coord.applying(displayTransform)
                            return SIMD2<Float>(Float(transformed.x), Float(transformed.y))
                        }

                        try TextureBillboardPipeline(specifierA: .texture2D(textureY), specifierB: .texture2D(textureCbCr), textureCoordinatesArray: transformedTexCoords, colorTransformFunctionName: "colorTransformYCbCrToRGB")

                        //                        try PBRShader {
                        //                            Draw(mtkMesh: teapot)
                        //                                .pbrUniforms(material: PBRMaterial.gold, modelTransform: .init(scale: [0.01, 0.01, 0.01]), cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix)
                        //                                .pbrLighting(lights)
                        //                                .pbrEnvironment(environmentTexture)
                        //                                .parameter("frameUniforms", functionType: .vertex, value: context.frameUniforms)
                        //                                .parameter("frameUniforms", functionType: .fragment, value: context.frameUniforms)
                        //                        }
                        //                        .vertexDescriptor(teapot.vertexDescriptor)
                        //                        .depthCompare(function: .less, enabled: true)

                        try ARAnchorsRenderPipeline(viewProjectionMatrix: viewProjectionMatrix, anchors: currentFrame.anchors, showMeshes: showMeshes, showPlanes: showPlanes, limitAnchors: limitAnchors)

                        try AxisLinesRenderPipeline(mvpMatrix: viewProjectionMatrix, scale: 10_000.0)
                    }
                }
            }
            .metalDepthStencilPixelFormat(.depth32Float)
            .metalClearColor(.init(red: 0, green: 0, blue: 0, alpha: 0))
            .onAppear {
                print("RenderView.onAppear")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if let cameraTrackingState = viewModel.cameraTrackingState, let currentFrame = viewModel.currentFrame {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tracking: \(String(describing: cameraTrackingState))")
                    Text("Y: \(viewModel.currentTextureY?.width ?? 0)x\(viewModel.currentTextureY?.height ?? 0)")
                    Text("CbCr: \(viewModel.currentTextureCbCr?.width ?? 0)x\(viewModel.currentTextureCbCr?.height ?? 0)")
                    Divider()
                    let meshAnchors = currentFrame.anchors.compactMap { $0 as? ARMeshAnchor }
                    let planeAnchors = currentFrame.anchors.compactMap { $0 as? ARPlaneAnchor }
                    Text("Total Anchors: \(currentFrame.anchors.count)")
                    Text("Mesh Anchors: \(meshAnchors.count)")
                    Text("Plane Anchors: \(planeAnchors.count)")
                    if let firstMesh = meshAnchors.first {
                        Text("Mesh Vertices: \(firstMesh.geometry.vertices.count)")
                        Text("Mesh Faces: \(firstMesh.geometry.faces.count)")
                    }
                    if let firstPlane = planeAnchors.first {
                        Text("Plane Vertices: \(firstPlane.geometry.vertices.count)")
                        Text("Plane Triangles: \(firstPlane.geometry.triangleIndices.count / 3)")
                        Text("Plane Boundary: \(firstPlane.geometry.boundaryVertices.count)")
                    }
                    Divider()
                    Toggle("Show Meshes", isOn: $showMeshes)
                    Toggle("Show Planes", isOn: $showPlanes)
                    Toggle("Limit to First", isOn: $limitAnchors)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding()
            }
        }
        .overlay {
            ARCoachingOverlayAdaptor(session: viewModel.session)
        }
    }
}

@Observable
class ARKitDemoViewModel: NSObject {
    var session: ARSession
    var configuration: ARConfiguration

    var cameraTrackingState: ARCamera.TrackingState?

    var currentFrame: ARFrame?
    var currentTextureY: MTLTexture?
    var currentTextureCbCr: MTLTexture?

    private var textureCache: CVMetalTextureCache?

    override init() {
        let device = _MTLCreateSystemDefaultDevice()

        session = .init()
        let configuration = ARWorldTrackingConfiguration()
        //        configuration.environmentTexturing = .automatic
        //        configuration.wantsHDREnvironmentTextures = true
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.sceneReconstruction = .meshWithClassification
        self.configuration = configuration

        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        self.textureCache = textureCache

        super.init()

        let arSessionDelegateQueue = DispatchQueue(label: "ar.session.delegate")
        session.delegateQueue = arSessionDelegateQueue

        session.delegate = self
        session.run(configuration, options: [])
    }

    func start() {
        // This line intentionally left blank.
    }
}

extension ARKitDemoViewModel: ARSessionObserver {
    func session(_ session: ARSession, didFailWithError error: any Error) {
        print(#function)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        print(#function)
        self.cameraTrackingState = camera.trackingState
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print(#function)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print(#function)
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        print(#function)
        return true
    }

    func session(_ session: ARSession, didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer) {
        print(#function)
    }

    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        print(#function)
    }

    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
        print(#function)
    }
}

extension ARKitDemoViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Extract texture from the captured image
        let capturedImage = frame.capturedImage
        let pixelBuffer = capturedImage
        guard let textureCache else {
            return
        }
        // ARKit provides YCbCr format with two planes
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return
        }

        // Create Y texture (luminance) from plane 0
        let widthY = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let heightY = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

        var cvMetalTextureY: CVMetalTexture?
        let statusY = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .r8Unorm, widthY, heightY, 0, &cvMetalTextureY)

        // Create CbCr texture (chrominance) from plane 1
        let widthCbCr = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let heightCbCr = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

        var cvMetalTextureCbCr: CVMetalTexture?
        let statusCbCr = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .rg8Unorm, widthCbCr, heightCbCr, 1, &cvMetalTextureCbCr)

        guard statusY == kCVReturnSuccess, let cvMetalTextureY, statusCbCr == kCVReturnSuccess, let cvMetalTextureCbCr else {
            return
        }

        currentFrame = frame
        currentTextureY = CVMetalTextureGetTexture(cvMetalTextureY)
        currentTextureY?.label = "AR Camera Y"
        currentTextureCbCr = CVMetalTextureGetTexture(cvMetalTextureCbCr)
        currentTextureCbCr?.label = "AR Camera CbCr"
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        print("Add anchors")
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        print("Update anchors")
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        print(#function)
    }
}

//
// let coachingOverlay = ARCoachingOverlayView()
// coachingOverlay.goal = .tracking
// coachingOverlay.activityType = .play
// coachingOverlay.feedback = .success
//
// view.addSubview(coachingOverlay)

struct ARCoachingOverlayAdaptor: View {
    let session: ARSession

    var body: some View {
        ViewAdaptor {
            ARCoachingOverlayView()
        }
        update: { (coachingOverlay: ARCoachingOverlayView) in
            coachingOverlay.session = session
        }
    }
}

#endif
