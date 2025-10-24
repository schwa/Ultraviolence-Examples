import AsyncAlgorithms
import CBORCoding
import Foundation
import Network
import simd

public struct NetworkMessage: Codable, Sendable {
    public enum Payload: Codable, Sendable {
        case cameraTransform(CameraTransform)
        case frameData(FrameData)
        case anchors([AnchorData])
        case roomData(RoomData)
        case cameraImage(CameraImageData)
    }

    let channel: String?
    let payload: Payload

    public init(channel: String, payload: Payload) {
        self.channel = channel
        self.payload = payload
    }
}

public actor NetworkClient {
    private var connection: NetworkConnection<Coder<NetworkMessage, NetworkMessage, NetworkCBORCoder>>?
    private var isConnected = false
    private var channels: [String?: (AsyncChannel<NetworkMessage>, Task<Void, Never>)] = [:]

    public init() {
        // This line intentionally left blank.
    }

    public func connect(type serviceType: String, onConnected: @escaping @Sendable () -> Void) async throws {
        guard !isConnected else {
            return
        }

        logger?.info("Connecting to Bonjour service: \(serviceType)")

        try await NetworkBrowser(for: .bonjour(serviceType)).run { endpoints in
            guard let endpoint = endpoints.first else {
                logger?.error("No endpoints found for service: \(serviceType)")
                return
            }

            self.connection = NetworkConnection(to: endpoint) {
                Coder(NetworkMessage.self, using: NetworkCBORCoder()) {
                    TCP()
                }
            }

            self.isConnected = true
            logger?.info("Connected to \(String(describing: endpoint))")
            onConnected()
        }
    }

    public var connected: Bool {
        isConnected
    }

    public func addChannel(_ name: String) {
        guard channels[name] == nil else {
            logger?.info("Channel \(name) already exists.")
            return
        }
        let channel = AsyncChannel<NetworkMessage>()
        let task = Task {
            let throttle = name == "frame" ? 1_000.0 / 60.0 : 1_000.0

            for await message in channel._throttle(for: .milliseconds(throttle), latest: true) {
                do {
                    try await sendRaw(message)
                }
                catch {
                    logger?.log("Error handling channel message: \(error)")
                }
            }
        }
        channels[name] = (channel, task)
    }

    public func removeChannel(_ name: String) {
        guard let (channel, _) = channels[name] else {
            logger?.info("Channel \(name) doesn't exist.")
            return
        }
        // Finish the channel to stop accepting new messages
        // The task will naturally complete after draining remaining messages
        channel.finish()
        channels[name] = nil
        // Don't cancel the task - let it complete naturally
    }

    public func send(_ message: NetworkMessage) async throws {
        if let (channel, _) = channels[message.channel] {
            await channel.send(message)
        }
        else {
            try await sendRaw(message)
        }
    }

    private func sendRaw(_ message: NetworkMessage) async throws {
        guard let connection, isConnected else {
            throw NetworkError.notConnected
        }
        do {
            try await connection.send(message)
        } catch {
            logger?.error("Send failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func disconnect() {
        logger?.info("Disconnected")
        connection = nil
        isConnected = false
    }
}

public enum NetworkError: Error {
    case notConnected
}

public struct CameraTransform: Codable, Sendable {
    let matrix: [Float]

    public init(matrix: float4x4) {
        self.matrix = [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
    }

    public var float4x4: simd.float4x4 {
        simd.float4x4(
            SIMD4(matrix[0], matrix[1], matrix[2], matrix[3]),
            SIMD4(matrix[4], matrix[5], matrix[6], matrix[7]),
            SIMD4(matrix[8], matrix[9], matrix[10], matrix[11]),
            SIMD4(matrix[12], matrix[13], matrix[14], matrix[15])
        )
    }
}

public struct FrameData: Codable, Sendable {
    let transform: [Float]
    let eulerAngles: [Float]
    let intrinsics: [Float]
    let imageResolution: [Float]
    let exposureDuration: Double
    let exposureOffset: Float
    let timestamp: Double
    let trackingState: String
    let trackingStateReason: String?
    let lightEstimate: LightEstimateData?

    public struct LightEstimateData: Codable, Sendable {
        let ambientIntensity: Float
        let ambientColorTemperature: Float
        let primaryLightDirection: [Float]?
        let primaryLightIntensity: Float?
    }
}

public struct AnchorData: Codable, Sendable {
    let identifier: String
    let transform: [Float]
    let anchorType: String
    let planeGeometry: PlaneGeometry?
    let meshGeometry: MeshGeometry?

    public struct PlaneGeometry: Codable, Sendable, Hashable {
        let vertices: [[Float]]
    }

    public struct MeshGeometry: Codable, Sendable, Hashable {
        let vertexData: Data
        let vertexCount: Int
        let vertexStride: Int
        let faceData: Data
        let faceCount: Int
    }
}

extension AnchorData: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

// MARK: - RoomPlan Data

public struct RoomData: Codable, Sendable {
    let walls: [SurfaceData]
    let doors: [SurfaceData]
    let windows: [SurfaceData]
    let objects: [ObjectData]

    public struct SurfaceData: Codable, Sendable {
        let identifier: String
        let transform: [Float]
        let dimensions: [Float]
        let category: String?
        let confidence: String
        let curve: CurveData?

        public struct CurveData: Codable, Sendable {
            let controlPoints: [[Float]]
        }
    }

    public struct ObjectData: Codable, Sendable {
        let identifier: String
        let transform: [Float]
        let dimensions: [Float]
        let category: String
        let confidence: String
    }
}

// MARK: - Camera Image Data

public struct CameraImageData: Codable, Sendable {
    let widthY: Int
    let heightY: Int
    let planeYData: Data
    let widthCbCr: Int
    let heightCbCr: Int
    let planeCbCrData: Data
    let timestamp: Double
}

#if os(iOS)
import RoomPlan

extension RoomData {
    public init(capturedRoom: CapturedRoom) {
        walls = capturedRoom.walls.map { SurfaceData(surface: $0) }
        doors = capturedRoom.doors.map { SurfaceData(surface: $0) }
        windows = capturedRoom.windows.map { SurfaceData(surface: $0) }
        objects = capturedRoom.objects.map { ObjectData(object: $0) }
    }
}

extension RoomData.SurfaceData {
    init(surface: CapturedRoom.Surface) {
        identifier = surface.identifier.uuidString
        transform = [
            surface.transform.columns.0.x, surface.transform.columns.0.y, surface.transform.columns.0.z, surface.transform.columns.0.w,
            surface.transform.columns.1.x, surface.transform.columns.1.y, surface.transform.columns.1.z, surface.transform.columns.1.w,
            surface.transform.columns.2.x, surface.transform.columns.2.y, surface.transform.columns.2.z, surface.transform.columns.2.w,
            surface.transform.columns.3.x, surface.transform.columns.3.y, surface.transform.columns.3.z, surface.transform.columns.3.w
        ]
        dimensions = [surface.dimensions.x, surface.dimensions.y, surface.dimensions.z]
        category = String(describing: surface.category)
        confidence = String(describing: surface.confidence)

        // Note: RoomPlan curve data structure varies by platform
        // For now, we skip curve encoding on iOS
        self.curve = nil
    }
}

extension RoomData.ObjectData {
    init(object: CapturedRoom.Object) {
        identifier = object.identifier.uuidString
        transform = [
            object.transform.columns.0.x, object.transform.columns.0.y, object.transform.columns.0.z, object.transform.columns.0.w,
            object.transform.columns.1.x, object.transform.columns.1.y, object.transform.columns.1.z, object.transform.columns.1.w,
            object.transform.columns.2.x, object.transform.columns.2.y, object.transform.columns.2.z, object.transform.columns.2.w,
            object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z, object.transform.columns.3.w
        ]
        dimensions = [object.dimensions.x, object.dimensions.y, object.dimensions.z]
        category = String(describing: object.category)
        confidence = String(describing: object.confidence)
    }
}
#endif
