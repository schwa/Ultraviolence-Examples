#if os(iOS)
import ARKit
import AsyncAlgorithms
import CoreVideo
import Metal
import Observation
import RoomPlan
import Ultraviolence
import UltraviolenceSupport

@Observable
class CaptureDemoViewModel: NSObject {
    var session: ARSession
    var configuration: ARConfiguration

    var cameraTrackingState: ARCamera.TrackingState?

    var currentFrame: ARFrame?
    var currentTextureY: MTLTexture?
    var currentTextureCbCr: MTLTexture?

    private var textureCache: CVMetalTextureCache?

    var networkClient: NetworkClient?
    var isClientConnected = false

    var sendFrameData = true
    var sendAnchors = true
    var sendRoomData = true
    var sendCameraImages = false

    var meshAnchors: [(anchor: ARMeshAnchor, meshWithEdges: MeshWithEdges)] = []

    // RoomPlan
    var roomCaptureSession: RoomCaptureSession?
    var isRoomCaptureActive = false
    var finalRoom: CapturedRoom?
    var capturedRoomData: CapturedRoomData?

    override init() {
        let device = _MTLCreateSystemDefaultDevice()

        session = .init()
        let configuration = ARWorldTrackingConfiguration()
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

    // MARK: - RoomPlan

    func startRoomCapture() {
        guard !isRoomCaptureActive else {
            return
        }

        let captureSession = RoomCaptureSession(arSession: session)
        roomCaptureSession = captureSession

        let configuration = RoomCaptureSession.Configuration()
        captureSession.run(configuration: configuration)

        isRoomCaptureActive = true
        captureSession.delegate = self
    }

    func stopRoomCapture() {
        guard isRoomCaptureActive else {
            return
        }

        roomCaptureSession?.stop()
        isRoomCaptureActive = false
    }
}

extension CaptureDemoViewModel: ARSessionObserver {
    func session(_ session: ARSession, didFailWithError error: any Error) {
        // Handle session errors
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        cameraTrackingState = camera.trackingState
    }

    func sessionWasInterrupted(_ session: ARSession) {
        // Handle session interruption
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // Handle interruption end
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        true
    }

    func session(_ session: ARSession, didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer) {
        // Handle audio if needed
    }

    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        // Handle collaboration data if needed
    }

    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
        // Handle geo tracking if needed
    }
}

extension CaptureDemoViewModel: ARSessionDelegate {
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

        // Convert mesh anchors to Mesh objects with edges
        let convertedMeshAnchors = frame.anchors
            .compactMap { $0 as? ARMeshAnchor }
            .compactMap { anchor -> (anchor: ARMeshAnchor, meshWithEdges: MeshWithEdges)? in
                guard let mesh = Mesh(arMeshGeometry: anchor.geometry) else {
                    return nil
                }
                // Extract edges from the mesh
                let meshWithEdges = MeshWithEdges(mesh: mesh)
                return (anchor, meshWithEdges)
            }
        meshAnchors = convertedMeshAnchors

        // Send frame data if connected and enabled
        if isClientConnected, let networkClient, sendFrameData {
            // Extract frame data synchronously BEFORE creating Task to avoid retaining ARFrame
            let frameData = FrameData(frame: frame)
            let frameMessage = NetworkMessage(channel: "frame", payload: .frameData(frameData))
            Task {
                do {
                    try await networkClient.send(frameMessage)
                }
                catch {
                    logger?.error("Failed to send frame data: \(error)")
                }
            }
        }

        // Send camera image if connected and enabled
        if isClientConnected, let networkClient, sendCameraImages {
            // Extract pixel buffer data synchronously BEFORE creating Task
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            // Copy Y plane data
            guard let planeYBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
                return
            }
            let planeYBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let planeYHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let planeYData = Data(bytes: planeYBaseAddress, count: planeYBytesPerRow * planeYHeight)

            // Copy CbCr plane data
            guard let planeCbCrBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
                return
            }
            let planeCbCrBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let planeCbCrHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            let planeCbCrData = Data(bytes: planeCbCrBaseAddress, count: planeCbCrBytesPerRow * planeCbCrHeight)

            let cameraImage = CameraImageData(
                widthY: widthY,
                heightY: heightY,
                planeYData: planeYData,
                widthCbCr: widthCbCr,
                heightCbCr: heightCbCr,
                planeCbCrData: planeCbCrData,
                timestamp: frame.timestamp
            )
            let imageMessage = NetworkMessage(channel: "camera_image", payload: .cameraImage(cameraImage))
            Task {
                do {
                    try await networkClient.send(imageMessage)
                }
                catch {
                    logger?.error("Failed to send camera image: \(error)")
                }
            }
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard isClientConnected, let networkClient, sendAnchors else {
            return
        }

        Task {
            for anchor in anchors {
                let channel = "anchor:\(anchor.identifier.uuidString)"
                await networkClient.addChannel(channel)

                // Send initial anchor data
                if let anchorData = try? AnchorData(anchor: anchor) {
                    let message = NetworkMessage(channel: channel, payload: .anchors([anchorData]))
                    try? await networkClient.send(message)
                }
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard isClientConnected, let networkClient, sendAnchors else {
            return
        }

        Task {
            for anchor in anchors {
                if let anchorData = try? AnchorData(anchor: anchor) {
                    let channel = "anchor:\(anchor.identifier.uuidString)"
                    let message = NetworkMessage(channel: channel, payload: .anchors([anchorData]))
                    try? await networkClient.send(message)
                }
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let networkClient else {
            return
        }
        for anchor in anchors {
            Task {
                let channel = "anchor:\(anchor.identifier.uuidString)"
                await networkClient.removeChannel(channel)
            }
        }
    }
}

// MARK: - RoomCaptureSessionDelegate

extension CaptureDemoViewModel: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        finalRoom = room

        // Send room data if connected and enabled
        if isClientConnected, let networkClient, sendRoomData {
            let roomData = RoomData(capturedRoom: room)
            let message = NetworkMessage(channel: "room", payload: .roomData(roomData))
            Task {
                do {
                    try await networkClient.send(message)
                }
                catch {
                    logger?.error("Failed to send room data: \(error)")
                }
            }
        }
    }

    //    func captureSession(_ session: RoomCaptureSession, didAdd instruction: RoomCaptureSession.Instruction) {
    //        // Handle instruction
    //    }

    //    func captureSession(_ session: RoomCaptureSession, didRemove instruction: RoomCaptureSession.Instruction) {
    //        // Handle instruction removal
    //    }

    //    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
    //        // Handle instruction
    //    }

    //    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
    //        // Session started
    //    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        if error == nil {
            capturedRoomData = data
        }
    }
}

#endif
