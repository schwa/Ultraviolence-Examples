import CBORCoding
import Combine
import CoreTransferable
import GeometryLite3D
import Interaction3D
import Metal
import Network
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceSupport
import UltraviolenceUI
import UniformTypeIdentifiers

// MARK: - Persisted AR Session Data

struct ARSessionSnapshot: Codable, Transferable {
    var frameData: FrameData?
    var anchors: [AnchorData]
    var roomData: RoomData?
    var photoQuads: [PhotoQuadData]
    var cameraTrail: [CameraTrailPoint]
    var timestamp: Date

    struct PhotoQuadData: Codable {
        let transform: [Float]  // 16 floats for float4x4
        let imageData: CameraImageData
    }

    struct CameraTrailPoint: Codable {
        let transform: [Float]  // 16 floats for float4x4
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(
            for: Self.self,
            contentType: .json,
            encoder: ISO8601JSONEncoder(),
            decoder: ISO8601JSONDecoder()
        )
    }
}

// Custom encoder/decoder with ISO8601 date strategy
private struct ISO8601JSONEncoder: TopLevelEncoder {
    func encode<T>(_ value: T) throws -> Data where T: Encodable {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}

private struct ISO8601JSONDecoder: TopLevelDecoder {
    func decode<T>(_ type: T.Type, from: Data) throws -> T where T: Decodable {
        // Try ISO8601 first
        let iso8601Decoder = JSONDecoder()
        iso8601Decoder.dateDecodingStrategy = .iso8601
        do {
            return try iso8601Decoder.decode(type, from: from)
        } catch {
            // If ISO8601 fails, try with default strategy (deferredToDate = timestamp as number)
            let fallbackDecoder = JSONDecoder()
            fallbackDecoder.dateDecodingStrategy = .deferredToDate
            return try fallbackDecoder.decode(type, from: from)
        }
    }
}

public struct CaptureReceiverDemoView: View {
    @State
    private var isListening = false

    @State
    private var status: String = "Not listening"

    @State
    private var serviceName: String = ProcessInfo.processInfo.hostName

    @State
    private var serviceType: String = "_ultraviolence._tcp"

    @State
    private var actualPort: String = ""

    @State
    private var connectionCount: Int = 0

    @State
    private var messagesReceived: Int = 0

    @State
    private var bytesReceived: Int = 0

    @State
    private var bytesPerSecond: Double = 0

    @State
    private var lastBytesUpdate = Date()

    @State
    private var messagesPerSecond: Double = 0

    @State
    private var messagesInWindow: Int = 0

    @State
    private var totalBytesReceived: Int = 0

    @State
    private var cameraImagesReceived: Int = 0

    @State
    private var listenerTask: Task<Void, Never>?

    @State
    private var latestFrameData: FrameData?

    @State
    private var anchors: [String: AnchorData] = [:]

    @State
    private var anchorMeshes: [(mesh: MeshWithEdges, transform: simd_float4x4)] = []

    @State
    private var projection: any ProjectionProtocol = PerspectiveProjection()

    @State
    private var cameraMatrix: simd_float4x4 = .init(translation: [0, 0, 5])

    @State
    private var showServerPopover = false

    @State
    private var edgeLineWidth: Float = 1.0

    @State
    private var showingExporter = false

    @State
    private var showingImporter = false

    @State
    private var snapshotToExport: ARSessionSnapshot?

    @State
    private var roomData: RoomData?

    @State
    private var latestCameraImage: CameraImageData?

    @State
    private var cameraImageTexture: MTLTexture?

    @State
    private var photoQuads: [(transform: float4x4, imageData: CameraImageData)] = []

    @State
    private var showPhotoQuads = true

    @State
    private var renderPhotoTextures = false

    @State
    private var zoomPhotoQuads = false

    @State
    private var photoQuadTextures: [Double: (textureY: MTLTexture, textureCbCr: MTLTexture)] = [:]

    @State
    private var cameraTrail: [float4x4] = []

    @State
    private var showCameraTrail = false

    @State
    private var maxTrailLength = 100

    @State
    private var showCameraFrustum = true

    @State
    private var showPlanes = true

    @State
    private var showMeshes = true

    @State
    private var showRoomWalls = true

    @State
    private var showRoomDoors = true

    @State
    private var showRoomWindows = true

    @State
    private var showRoomObjects = true

    public init() {
        // This line intentionally left blank.
    }

    public var body: some View {
        let meshes = anchorMeshes  // Capture the meshes outside the view builder

        WorldView(projection: $projection, cameraMatrix: $cameraMatrix) {
            RenderView { _, drawableSize in
                let projectionMatrix = projection.projectionMatrix(for: drawableSize)
                let viewMatrix = cameraMatrix.inverse
                let viewProjection = projectionMatrix * viewMatrix

                try RenderPass {
                    try AxisLinesRenderPipeline(
                        mvpMatrix: viewProjection,
                        viewMatrix: viewMatrix,
                        projectionMatrix: projectionMatrix,
                        viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
                    )
                    if let frameData = latestFrameData {
                        let context = buildVisualization(frameData: frameData, anchors: anchors, roomData: roomData)
                        try GraphicsContext3DRenderPipeline(context: context, viewProjection: viewProjection, viewport: [Float(drawableSize.width), Float(drawableSize.height)], debugWireframe: false)
                    }

                    // Render mesh anchors using EdgeLinesRenderPass
                    if showMeshes {
                        try renderMeshAnchors(meshes: meshes, cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix, drawableSize: drawableSize)
                    }

                    // Render photo quads with textures
                    if showPhotoQuads, renderPhotoTextures {
                        try renderPhotoQuadTextures(viewProjection: viewProjection)
                    }
                }
            }
            .metalDepthStencilPixelFormat(.depth32Float)
        }
        .onAppear {
            if !isListening {
                startListening()
            }
        }
        .overlay(alignment: .topLeading) {
            Form {
                Section {
                    LabeledContent("Status", value: isListening ? "Listening" : "Stopped")
                        .foregroundStyle(isListening ? .green : .secondary)
                    LabeledContent("Bytes/sec", value: "\((bytesPerSecond / 1_024).formatted(.number.precision(.fractionLength(1)))) KB/s")
                    LabeledContent("Total Data", value: "\((Double(totalBytesReceived) / 1_048_576).formatted(.number.precision(.fractionLength(1)))) MB")
                    LabeledContent("Messages/sec", value: messagesPerSecond.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("Anchors", value: anchors.count.formatted())
                    LabeledContent("Planes", value: anchors.values.filter { $0.planeGeometry != nil }.count.formatted())
                    LabeledContent("Meshes", value: anchors.values.filter { $0.meshGeometry != nil }.count.formatted())
                    LabeledContent("Camera Images", value: cameraImagesReceived.formatted())
                        .foregroundStyle(cameraImagesReceived > 0 ? .green : .secondary)
                }

                if let roomData {
                    Section("RoomPlan") {
                        LabeledContent("Walls", value: roomData.walls.count.formatted())
                        LabeledContent("Doors", value: roomData.doors.count.formatted())
                        LabeledContent("Windows", value: roomData.windows.count.formatted())
                        LabeledContent("Objects", value: roomData.objects.count.formatted())
                    }
                }

                Section("Rendering") {
                    VStack(alignment: .leading) {
                        Text("Edge Line Width: \(edgeLineWidth.formatted(.number.precision(.fractionLength(1))))")
                        Slider(value: $edgeLineWidth, in: 0.5...10.0, step: 0.5)
                    }
                }

                Section("Camera") {
                    Toggle("Show Camera Frustum", isOn: $showCameraFrustum)
                    Toggle("Show Camera Trail", isOn: $showCameraTrail)
                    if showCameraTrail {
                        VStack(alignment: .leading) {
                            Text("Trail Length: \(maxTrailLength)")
                            Slider(
                                value: Binding(
                                    get: { Double(maxTrailLength) },
                                    set: { maxTrailLength = Int($0) }
                                ),
                                in: 10...500,
                                step: 10
                            )
                        }
                        Button("Clear Trail") {
                            cameraTrail.removeAll()
                        }
                    }
                    Toggle("Show Photo Quads", isOn: $showPhotoQuads)
                    if showPhotoQuads {
                        Toggle("Render Photo Textures", isOn: $renderPhotoTextures)
                            .disabled(photoQuads.isEmpty)
                        Toggle("Zoom Photo Quads (2x)", isOn: $zoomPhotoQuads)
                            .disabled(photoQuads.isEmpty)
                    }
                    if showPhotoQuads, !photoQuads.isEmpty {
                        Button("Clear Photos (\(photoQuads.count))") {
                            photoQuads.removeAll()
                            photoQuadTextures.removeAll()
                            cameraImagesReceived = 0
                        }
                    }
                }

                Section("AR Elements") {
                    Toggle("Show Planes", isOn: $showPlanes)
                    Toggle("Show Meshes", isOn: $showMeshes)
                }

                if roomData != nil {
                    Section("RoomPlan Elements") {
                        Toggle("Show Walls", isOn: $showRoomWalls)
                        Toggle("Show Doors", isOn: $showRoomDoors)
                        Toggle("Show Windows", isOn: $showRoomWindows)
                        Toggle("Show Objects", isOn: $showRoomObjects)
                    }
                }

                Section("Color Key - AR") {
                    HStack {
                        Circle().fill(.green).frame(width: 10, height: 10)
                        Text("Camera Frustum (Normal)")
                    }
                    HStack {
                        Circle().fill(.orange).frame(width: 10, height: 10)
                        Text("Camera Frustum (Limited)")
                    }
                    HStack {
                        Circle().fill(.white.opacity(0.5)).frame(width: 10, height: 10)
                        Text("Camera Trail")
                    }
                    HStack {
                        Circle().fill(.cyan.opacity(0.7)).frame(width: 10, height: 10)
                        Text("Trail Orientation")
                    }
                    HStack {
                        Circle().fill(.red).frame(width: 10, height: 10)
                        Text("Camera X-Axis")
                    }
                    HStack {
                        Circle().fill(.green).frame(width: 10, height: 10)
                        Text("Camera Y-Axis")
                    }
                    HStack {
                        Circle().fill(.blue).frame(width: 10, height: 10)
                        Text("Camera Z-Axis")
                    }
                    HStack {
                        Circle().fill(.cyan).frame(width: 10, height: 10)
                        Text("Plane Boundaries")
                    }
                    HStack {
                        Circle().fill(.purple).frame(width: 10, height: 10)
                        Text("Mesh Geometry")
                    }
                    HStack {
                        Circle().fill(.pink).frame(width: 10, height: 10)
                        Text("Photo Quads")
                    }
                }

                if roomData != nil {
                    Section("Color Key - RoomPlan") {
                        HStack {
                            Circle().fill(.yellow).frame(width: 10, height: 10)
                            Text("Walls")
                        }
                        HStack {
                            Circle().fill(.green).frame(width: 10, height: 10)
                            Text("Doors")
                        }
                        HStack {
                            Circle().fill(.blue).frame(width: 10, height: 10)
                            Text("Windows")
                        }
                        HStack {
                            Circle().fill(.orange).frame(width: 10, height: 10)
                            Text("Objects")
                        }
                    }
                }
            }
            .frame(width: 350)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showServerPopover = true
                } label: {
                    Image(systemName: isListening ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(isListening ? .green : .secondary)
                        .accessibilityLabel(isListening ? "Server listening" : "Server not listening")
                }
                .popover(isPresented: $showServerPopover) {
                    Form {
                        Section("Server") {
                            LabeledContent("Status", value: status)
                            LabeledContent("Service Name", value: serviceName)
                            if !actualPort.isEmpty {
                                LabeledContent("Port", value: actualPort)
                            }
                            LabeledContent("Service Type") {
                                TextField("Service Type", text: $serviceType)
                                    .disabled(isListening)
                            }
                            LabeledContent("Connections", value: connectionCount.formatted())
                            LabeledContent("Messages", value: messagesReceived.formatted())
                            Button(isListening ? "Stop Listening" : "Start Listening") {
                                if isListening {
                                    stopListening()
                                } else {
                                    startListening()
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(minWidth: 300)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Convert photoQuads to Codable format
                    let photoQuadsData = photoQuads.map { quad in
                        let t = quad.transform
                        return ARSessionSnapshot.PhotoQuadData(
                            transform: [
                                t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
                                t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
                                t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
                                t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w
                            ],
                            imageData: quad.imageData
                        )
                    }

                    // Convert camera trail to Codable format
                    let trailData = cameraTrail.map { transform in
                        ARSessionSnapshot.CameraTrailPoint(
                            transform: [
                                transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w,
                                transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w,
                                transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w,
                                transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w
                            ]
                        )
                    }

                    snapshotToExport = ARSessionSnapshot(
                        frameData: latestFrameData,
                        anchors: Array(anchors.values),
                        roomData: roomData,
                        photoQuads: photoQuadsData,
                        cameraTrail: trailData,
                        timestamp: Date()
                    )
                    showingExporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .accessibilityLabel("Save AR Session")
                }
                .disabled(anchors.isEmpty && latestFrameData == nil && photoQuads.isEmpty && roomData == nil)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel("Load AR Session")
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            item: snapshotToExport,
            contentTypes: [.json],
            defaultFilename: "ar-session-\(ISO8601DateFormatter().string(from: Date())).json"
        ) { _ in
            // Export completed
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }

                guard url.startAccessingSecurityScopedResource() else {
                    return
                }

                defer {
                    url.stopAccessingSecurityScopedResource()
                }

                do {
                    let data = try Data(contentsOf: url)
                    let decoder = ISO8601JSONDecoder()
                    let snapshot = try decoder.decode(ARSessionSnapshot.self, from: data)

                    latestFrameData = snapshot.frameData
                    // Convert array to dictionary
                    anchors = Dictionary(uniqueKeysWithValues: snapshot.anchors.map { ($0.identifier, $0) })

                    // Restore RoomPlan data
                    roomData = snapshot.roomData

                    // Restore photo quads
                    photoQuads = snapshot.photoQuads.map { quadData in
                        let t = quadData.transform
                        let transform = float4x4(
                            SIMD4(t[0], t[1], t[2], t[3]),
                            SIMD4(t[4], t[5], t[6], t[7]),
                            SIMD4(t[8], t[9], t[10], t[11]),
                            SIMD4(t[12], t[13], t[14], t[15])
                        )
                        return (transform: transform, imageData: quadData.imageData)
                    }
                    cameraImagesReceived = photoQuads.count

                    // Restore camera trail
                    cameraTrail = snapshot.cameraTrail.map { point in
                        let t = point.transform
                        return float4x4(
                            SIMD4(t[0], t[1], t[2], t[3]),
                            SIMD4(t[4], t[5], t[6], t[7]),
                            SIMD4(t[8], t[9], t[10], t[11]),
                            SIMD4(t[12], t[13], t[14], t[15])
                        )
                    }

                    let device = _MTLCreateSystemDefaultDevice()
                    var convertedMeshes: [(mesh: MeshWithEdges, transform: simd_float4x4)] = []
                    for anchor in snapshot.anchors {
                        if let meshGeometry = anchor.meshGeometry, let meshWithEdges = convertMeshGeometry(meshGeometry, device: device) {
                            let transform = float4x4(
                                SIMD4(anchor.transform[0], anchor.transform[1], anchor.transform[2], anchor.transform[3]),
                                SIMD4(anchor.transform[4], anchor.transform[5], anchor.transform[6], anchor.transform[7]),
                                SIMD4(anchor.transform[8], anchor.transform[9], anchor.transform[10], anchor.transform[11]),
                                SIMD4(anchor.transform[12], anchor.transform[13], anchor.transform[14], anchor.transform[15])
                            )
                            convertedMeshes.append((mesh: meshWithEdges, transform: transform))
                        }
                    }
                    anchorMeshes = convertedMeshes
                } catch {
                    // Failed to load
                }

            case .failure:
                break
            }
        }
    }

    private func startListening() {
        guard !isListening else {
            return
        }
        isListening = true
        status = "Starting..."
        connectionCount = 0

        listenerTask = Task {
            await listen()
        }
    }

    private func stopListening() {
        listenerTask?.cancel()
        listenerTask = nil
        isListening = false
        status = "Stopped"
    }

    private func listen() async {
        await MainActor.run {
            status = "Starting listener..."
        }

        do {
            try await NetworkListener(for: .bonjour(name: serviceName, type: serviceType)) {
                Coder(NetworkMessage.self, using: NetworkCBORCoder()) {
                    TCP()
                }
            }
            .run { connection in
                await MainActor.run {
                    if actualPort.isEmpty {
                        status = "Listening on Bonjour service '\(serviceName)'"
                    }
                    connectionCount += 1
                    status = "Connection from \(connection)"
                }

                defer {
                    Task { @MainActor in
                        connectionCount -= 1
                    }
                }

                do {
                    for try await (message, _) in connection.messages {
                        await MainActor.run {
                            messagesReceived += 1
                            messagesInWindow += 1
                            let messageBytes = (try? CBOREncoder().encode(message))?.count ?? 0
                            bytesReceived += messageBytes
                            totalBytesReceived += messageBytes
                            let now = Date()
                            let elapsed = now.timeIntervalSince(lastBytesUpdate)
                            if elapsed >= 1.0 {
                                bytesPerSecond = Double(bytesReceived) / elapsed
                                messagesPerSecond = Double(messagesInWindow) / elapsed
                                bytesReceived = 0
                                messagesInWindow = 0
                                lastBytesUpdate = now
                            }
                            switch message.payload {
                            case .cameraTransform:
                                status = "Received: Camera Transform"
                            case .frameData(let frameData):
                                status = "Received: AR Frame Data"
                                latestFrameData = frameData

                                // Track camera transform for trail
                                if showCameraTrail {
                                    let transform = float4x4(
                                        SIMD4(frameData.transform[0], frameData.transform[1], frameData.transform[2], frameData.transform[3]),
                                        SIMD4(frameData.transform[4], frameData.transform[5], frameData.transform[6], frameData.transform[7]),
                                        SIMD4(frameData.transform[8], frameData.transform[9], frameData.transform[10], frameData.transform[11]),
                                        SIMD4(frameData.transform[12], frameData.transform[13], frameData.transform[14], frameData.transform[15])
                                    )
                                    cameraTrail.append(transform)
                                    if cameraTrail.count > maxTrailLength {
                                        cameraTrail.removeFirst()
                                    }
                                }
                            case .anchors(let anchorData):
                                // Update anchors dictionary with new data
                                for anchor in anchorData {
                                    anchors[anchor.identifier] = anchor
                                }

                                // Rebuild meshes from all anchors
                                let device = _MTLCreateSystemDefaultDevice()
                                var convertedMeshes: [(mesh: MeshWithEdges, transform: simd_float4x4)] = []
                                for anchor in anchors.values {
                                    if let meshGeometry = anchor.meshGeometry, let meshWithEdges = convertMeshGeometry(meshGeometry, device: device) {
                                        let transform = float4x4(
                                            SIMD4(anchor.transform[0], anchor.transform[1], anchor.transform[2], anchor.transform[3]),
                                            SIMD4(anchor.transform[4], anchor.transform[5], anchor.transform[6], anchor.transform[7]),
                                            SIMD4(anchor.transform[8], anchor.transform[9], anchor.transform[10], anchor.transform[11]),
                                            SIMD4(anchor.transform[12], anchor.transform[13], anchor.transform[14], anchor.transform[15])
                                        )
                                        convertedMeshes.append((mesh: meshWithEdges, transform: transform))
                                    }
                                }
                                anchorMeshes = convertedMeshes
                            case .roomData(let room):
                                status = "Received: RoomPlan Data"
                                roomData = room
                            case .cameraImage(let imageData):
                                status = "Received: Camera Image (\(photoQuads.count) quads)"
                                latestCameraImage = imageData
                                cameraImagesReceived += 1

                                // Store photo quad at current camera position
                                if let frameData = latestFrameData {
                                    let transform = float4x4(
                                        SIMD4(frameData.transform[0], frameData.transform[1], frameData.transform[2], frameData.transform[3]),
                                        SIMD4(frameData.transform[4], frameData.transform[5], frameData.transform[6], frameData.transform[7]),
                                        SIMD4(frameData.transform[8], frameData.transform[9], frameData.transform[10], frameData.transform[11]),
                                        SIMD4(frameData.transform[12], frameData.transform[13], frameData.transform[14], frameData.transform[15])
                                    )
                                    photoQuads.append((transform: transform, imageData: imageData))
                                    print("📸 Photo quad added at position: (\(transform.columns.3.x), \(transform.columns.3.y), \(transform.columns.3.z)). Total quads: \(photoQuads.count)")
                                } else {
                                    print("⚠️ No frameData available when camera image received")
                                }
                            // TODO: Create texture from YCbCr data
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        status = "Connection error: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            await MainActor.run {
                status = "Failed: \(error.localizedDescription)"
                isListening = false
            }
        }
    }

    @ElementBuilder
    private func renderMeshAnchors(meshes: [(mesh: MeshWithEdges, transform: simd_float4x4)], cameraMatrix: simd_float4x4, projectionMatrix: simd_float4x4, drawableSize: CGSize) throws -> some Element {
        ForEach(Array(meshes.enumerated()), id: \.offset) { _, element in
            let (meshWithEdges, transform) = element
            let transforms = Transforms(
                modelMatrix: transform,
                cameraMatrix: cameraMatrix,
                projectionMatrix: projectionMatrix
            )
            try EdgeLinesRenderPass(
                meshWithEdges: meshWithEdges,
                transforms: transforms,
                lineWidth: edgeLineWidth,
                viewport: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
                colorizeByTriangle: false,
                edgeColor: SIMD4<Float>(0.5, 0.0, 0.5, 1.0),  // Purple
                debugMode: false
            )
        }
    }

    @ElementBuilder
    private func renderPhotoQuadTextures(viewProjection: simd_float4x4) throws -> some Element {
        ForEach(Array(photoQuads.enumerated()), id: \.offset) { _, photoQuad in
            let verts = calculateQuadVertices(photoQuad: photoQuad)
            let texCoords = calculateQuadTexCoords()

            // Get or create textures
            let key = photoQuad.imageData.timestamp
            let device = _MTLCreateSystemDefaultDevice()
            let textures: (textureY: MTLTexture, textureCbCr: MTLTexture)? = {
                if let cached = photoQuadTextures[key] {
                    return cached
                }
                if let created = createTexturesFromImageData(photoQuad.imageData, device: device) {
                    photoQuadTextures[key] = created
                    return created
                }
                return nil
            }()

            if let textures {
                TexturedQuad3DPipeline(
                    vertices: verts,
                    textureCoords: texCoords,
                    textureY: textures.textureY,
                    textureCbCr: textures.textureCbCr,
                    mvpMatrix: viewProjection
                )
            }
        }
    }

    private func calculateQuadVertices(photoQuad: (transform: float4x4, imageData: CameraImageData)) -> [SIMD3<Float>] {
        let quadTransform = photoQuad.transform
        let pos = SIMD3<Float>(quadTransform.columns.3.x, quadTransform.columns.3.y, quadTransform.columns.3.z)
        let r = SIMD3<Float>(quadTransform.columns.0.x, quadTransform.columns.0.y, quadTransform.columns.0.z)
        let u = SIMD3<Float>(quadTransform.columns.1.x, quadTransform.columns.1.y, quadTransform.columns.1.z)
        let f = -SIMD3<Float>(quadTransform.columns.2.x, quadTransform.columns.2.y, quadTransform.columns.2.z)

        let ar = Float(photoQuad.imageData.widthY) / Float(photoQuad.imageData.heightY)
        let baseHeight: Float = 0.3
        let zoomMultiplier: Float = zoomPhotoQuads ? 2.0 : 1.0
        let h = baseHeight * zoomMultiplier
        let w = h * ar
        let center = pos + f * 0.4
        let hw = w / 2
        let hh = h / 2

        return [
            center - r * hw - u * hh,
            center + r * hw - u * hh,
            center - r * hw + u * hh,
            center + r * hw + u * hh
        ]
    }

    private func calculateQuadTexCoords() -> [SIMD2<Float>] {
        [
            SIMD2<Float>(0, 1),
            SIMD2<Float>(1, 1),
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 0)
        ]
    }

    // MARK: - Mesh Conversion

    // TODO: Deprecate.
    private func convertMeshGeometry(_ meshGeometry: AnchorData.MeshGeometry, device: MTLDevice) -> MeshWithEdges? {
        // Create vertex buffer from vertex data
        guard let vertexBuffer = meshGeometry.vertexData.withUnsafeBytes({ bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress else {
                return nil
            }
            return device.makeBuffer(bytes: baseAddress, length: meshGeometry.vertexData.count, options: [])
        }) else {
            return nil
        }
        vertexBuffer.label = "AR Mesh Vertices"

        // Create index buffer from face data
        guard let indexBuffer = meshGeometry.faceData.withUnsafeBytes({ bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress else {
                return nil
            }
            return device.makeBuffer(bytes: baseAddress, length: meshGeometry.faceData.count, options: [])
        }) else {
            return nil
        }
        indexBuffer.label = "AR Mesh Indices"

        // Create vertex descriptor (position only for AR mesh - SIMD3<Float>)
        let vertexDescriptor = VertexDescriptor(
            label: "AR Mesh",
            attributes: [
                .init(semantic: .position, format: .float3, offset: 0, bufferIndex: 0)
            ],
            layouts: [
                .init(bufferIndex: 0, stride: meshGeometry.vertexStride, stepFunction: .perVertex, stepRate: 1)
            ]
        )

        // Create mesh
        let mesh = Mesh(
            label: "AR Mesh",
            submeshes: [
                Mesh.Submesh(
                    label: nil,
                    primitiveType: .triangle,
                    indices: Mesh.Buffer(
                        buffer: indexBuffer,
                        count: meshGeometry.faceCount * 3,  // 3 indices per triangle
                        offset: 0
                    )
                )
            ],
            vertexDescriptor: vertexDescriptor,
            vertexBuffers: [
                Mesh.Buffer(
                    buffer: vertexBuffer,
                    count: meshGeometry.vertexCount,
                    offset: 0
                )
            ]
        )

        // Use MeshWithEdges convenience initializer to extract edges
        return MeshWithEdges(mesh: mesh)
    }

    private func buildVisualization(frameData: FrameData, anchors: [String: AnchorData], roomData: RoomData?) -> GraphicsContext3D {
        GraphicsContext3D { context in
            // Draw camera trail with orientation markers
            if showCameraTrail, cameraTrail.count > 1 {
                // Draw trail line connecting positions
                let trailPath = Path3D { path in
                    let pos0 = SIMD3<Float>(cameraTrail[0].columns.3.x, cameraTrail[0].columns.3.y, cameraTrail[0].columns.3.z)
                    path.move(to: pos0)
                    for i in 1..<cameraTrail.count {
                        let pos = SIMD3<Float>(cameraTrail[i].columns.3.x, cameraTrail[i].columns.3.y, cameraTrail[i].columns.3.z)
                        path.addLine(to: pos)
                    }
                }
                context.stroke(trailPath, with: .white.opacity(0.5), lineWidth: 2.0)

                // Draw orientation markers at intervals
                let interval = max(1, cameraTrail.count / 20)
                for i in stride(from: 0, to: cameraTrail.count, by: interval) {
                    let trailTransform = cameraTrail[i]
                    let trailPos = SIMD3<Float>(trailTransform.columns.3.x, trailTransform.columns.3.y, trailTransform.columns.3.z)
                    let trailForward = -SIMD3<Float>(trailTransform.columns.2.x, trailTransform.columns.2.y, trailTransform.columns.2.z)
                    let markerLen: Float = 0.05

                    let forwardPath = Path3D { path in
                        path.move(to: trailPos)
                        path.addLine(to: trailPos + trailForward * markerLen)
                    }
                    context.stroke(forwardPath, with: .cyan.opacity(0.7), lineWidth: 1.5)
                }
            }

            let transform = float4x4(SIMD4(frameData.transform[0], frameData.transform[1], frameData.transform[2], frameData.transform[3]), SIMD4(frameData.transform[4], frameData.transform[5], frameData.transform[6], frameData.transform[7]), SIMD4(frameData.transform[8], frameData.transform[9], frameData.transform[10], frameData.transform[11]), SIMD4(frameData.transform[12], frameData.transform[13], frameData.transform[14], frameData.transform[15]))
            let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let right = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
            let up = SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
            let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            let frustumDepth: Float = 0.3
            let frustumWidth: Float = 0.15
            let frustumHeight: Float = 0.1
            let nearTopLeft = position + forward * frustumDepth + up * frustumHeight + right * -frustumWidth
            let nearTopRight = position + forward * frustumDepth + up * frustumHeight + right * frustumWidth
            let nearBottomLeft = position + forward * frustumDepth + up * -frustumHeight + right * -frustumWidth
            let nearBottomRight = position + forward * frustumDepth + up * -frustumHeight + right * frustumWidth
            if showCameraFrustum {
                let frustumPath = Path3D { path in
                    path.move(to: position)
                    path.addLine(to: nearTopLeft)
                    path.move(to: position)
                    path.addLine(to: nearTopRight)
                    path.move(to: position)
                    path.addLine(to: nearBottomLeft)
                    path.move(to: position)
                    path.addLine(to: nearBottomRight)
                    path.move(to: nearTopLeft)
                    path.addLine(to: nearTopRight)
                    path.addLine(to: nearBottomRight)
                    path.addLine(to: nearBottomLeft)
                    path.closeSubpath()
                }
                let frustumColor: Color = frameData.trackingState == "normal" ? .green : .orange
                context.stroke(frustumPath, with: frustumColor, lineWidth: 3.0)
                let axisLength: Float = 0.1
                let xAxisPath = Path3D { path in
                    path.move(to: position)
                    path.addLine(to: position + right * axisLength)
                }
                context.stroke(xAxisPath, with: .red, lineWidth: 2.0)
                let yAxisPath = Path3D { path in
                    path.move(to: position)
                    path.addLine(to: position + up * axisLength)
                }
                context.stroke(yAxisPath, with: .green, lineWidth: 2.0)
                let zAxisPath = Path3D { path in
                    path.move(to: position)
                    path.addLine(to: position + forward * axisLength)
                }
                context.stroke(zAxisPath, with: .blue, lineWidth: 2.0)
            }
            for anchor in anchors.values {
                let anchorTransform = float4x4(SIMD4(anchor.transform[0], anchor.transform[1], anchor.transform[2], anchor.transform[3]), SIMD4(anchor.transform[4], anchor.transform[5], anchor.transform[6], anchor.transform[7]), SIMD4(anchor.transform[8], anchor.transform[9], anchor.transform[10], anchor.transform[11]), SIMD4(anchor.transform[12], anchor.transform[13], anchor.transform[14], anchor.transform[15]))
                if let planeGeometry = anchor.planeGeometry, showPlanes {
                    let planePath = Path3D { path in
                        guard !planeGeometry.vertices.isEmpty else {
                            return
                        }
                        let firstVertex = planeGeometry.vertices[0]
                        let firstPoint = SIMD3<Float>(firstVertex[0], firstVertex[1], firstVertex[2])
                        let transformedFirst = anchorTransform * SIMD4<Float>(firstPoint.x, firstPoint.y, firstPoint.z, 1.0)
                        path.move(to: SIMD3<Float>(transformedFirst.x, transformedFirst.y, transformedFirst.z))
                        for i in 1..<planeGeometry.vertices.count {
                            let vertex = planeGeometry.vertices[i]
                            let point = SIMD3<Float>(vertex[0], vertex[1], vertex[2])
                            let transformed = anchorTransform * SIMD4<Float>(point.x, point.y, point.z, 1.0)
                            path.addLine(to: SIMD3<Float>(transformed.x, transformed.y, transformed.z))
                        }
                        path.closeSubpath()
                    }
                    context.stroke(planePath, with: .cyan, lineWidth: 2.0)
                } else if anchor.meshGeometry == nil {
                    // Only render anchor markers for non-mesh, non-plane anchors
                    let anchorPosition = SIMD3<Float>(anchorTransform.columns.3.x, anchorTransform.columns.3.y, anchorTransform.columns.3.z)
                    let anchorRight = SIMD3<Float>(anchorTransform.columns.0.x, anchorTransform.columns.0.y, anchorTransform.columns.0.z)
                    let anchorUp = SIMD3<Float>(anchorTransform.columns.1.x, anchorTransform.columns.1.y, anchorTransform.columns.1.z)
                    let cubeSize: Float = 0.05
                    let cubePath = Path3D { path in
                        let p1 = anchorPosition + anchorRight * -cubeSize + anchorUp * -cubeSize
                        let p2 = anchorPosition + anchorRight * cubeSize + anchorUp * -cubeSize
                        let p3 = anchorPosition + anchorRight * cubeSize + anchorUp * cubeSize
                        let p4 = anchorPosition + anchorRight * -cubeSize + anchorUp * cubeSize
                        path.move(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: p4)
                        path.closeSubpath()
                    }
                    context.stroke(cubePath, with: .white, lineWidth: 2.0)
                }
            }

            // Render RoomPlan data
            if let roomData {
                // Render walls in yellow
                if showRoomWalls {
                    for wall in roomData.walls {
                        let wallTransform = float4x4(
                            SIMD4(wall.transform[0], wall.transform[1], wall.transform[2], wall.transform[3]),
                            SIMD4(wall.transform[4], wall.transform[5], wall.transform[6], wall.transform[7]),
                            SIMD4(wall.transform[8], wall.transform[9], wall.transform[10], wall.transform[11]),
                            SIMD4(wall.transform[12], wall.transform[13], wall.transform[14], wall.transform[15])
                        )
                        let dimensions = SIMD3<Float>(wall.dimensions[0], wall.dimensions[1], wall.dimensions[2])
                        let boxPath = createBoxPath(transform: wallTransform, dimensions: dimensions)
                        context.stroke(boxPath, with: .yellow, lineWidth: 3.0)
                    }
                }

                // Render doors in green
                if showRoomDoors {
                    for door in roomData.doors {
                        let doorTransform = float4x4(
                            SIMD4(door.transform[0], door.transform[1], door.transform[2], door.transform[3]),
                            SIMD4(door.transform[4], door.transform[5], door.transform[6], door.transform[7]),
                            SIMD4(door.transform[8], door.transform[9], door.transform[10], door.transform[11]),
                            SIMD4(door.transform[12], door.transform[13], door.transform[14], door.transform[15])
                        )
                        let dimensions = SIMD3<Float>(door.dimensions[0], door.dimensions[1], door.dimensions[2])
                        let boxPath = createBoxPath(transform: doorTransform, dimensions: dimensions)
                        context.stroke(boxPath, with: .green, lineWidth: 3.0)
                    }
                }

                // Render windows in blue
                if showRoomWindows {
                    for window in roomData.windows {
                        let windowTransform = float4x4(
                            SIMD4(window.transform[0], window.transform[1], window.transform[2], window.transform[3]),
                            SIMD4(window.transform[4], window.transform[5], window.transform[6], window.transform[7]),
                            SIMD4(window.transform[8], window.transform[9], window.transform[10], window.transform[11]),
                            SIMD4(window.transform[12], window.transform[13], window.transform[14], window.transform[15])
                        )
                        let dimensions = SIMD3<Float>(window.dimensions[0], window.dimensions[1], window.dimensions[2])
                        let boxPath = createBoxPath(transform: windowTransform, dimensions: dimensions)
                        context.stroke(boxPath, with: .blue, lineWidth: 3.0)
                    }
                }

                // Render objects in orange
                if showRoomObjects {
                    for object in roomData.objects {
                        let objectTransform = float4x4(
                            SIMD4(object.transform[0], object.transform[1], object.transform[2], object.transform[3]),
                            SIMD4(object.transform[4], object.transform[5], object.transform[6], object.transform[7]),
                            SIMD4(object.transform[8], object.transform[9], object.transform[10], object.transform[11]),
                            SIMD4(object.transform[12], object.transform[13], object.transform[14], object.transform[15])
                        )
                        let dimensions = SIMD3<Float>(object.dimensions[0], object.dimensions[1], object.dimensions[2])
                        let boxPath = createBoxPath(transform: objectTransform, dimensions: dimensions)
                        context.stroke(boxPath, with: .orange, lineWidth: 3.0)
                    }
                }
            }

            // Render photo quads
            if showPhotoQuads {
                for photoQuad in photoQuads {
                    let quadTransform = photoQuad.transform
                    let pos = SIMD3<Float>(quadTransform.columns.3.x, quadTransform.columns.3.y, quadTransform.columns.3.z)
                    let r = SIMD3<Float>(quadTransform.columns.0.x, quadTransform.columns.0.y, quadTransform.columns.0.z)
                    let u = SIMD3<Float>(quadTransform.columns.1.x, quadTransform.columns.1.y, quadTransform.columns.1.z)
                    let f = -SIMD3<Float>(quadTransform.columns.2.x, quadTransform.columns.2.y, quadTransform.columns.2.z)

                    // Calculate quad size
                    let ar = Float(photoQuad.imageData.widthY) / Float(photoQuad.imageData.heightY)
                    let h: Float = 0.3
                    let w = h * ar

                    // Position quad in front of camera
                    let center = pos + f * 0.4

                    // Create corners
                    let hw = w / 2
                    let hh = h / 2
                    let tl = center - r * hw + u * hh
                    let tr = center + r * hw + u * hh
                    let bl = center - r * hw - u * hh
                    let br = center + r * hw - u * hh

                    // Draw quad outline
                    let quadPath = Path3D { path in
                        path.move(to: tl)
                        path.addLine(to: tr)
                        path.addLine(to: br)
                        path.addLine(to: bl)
                        path.closeSubpath()
                    }
                    context.stroke(quadPath, with: .pink, lineWidth: 2.0)
                }
            }
        }
    }

    private func createBoxPath(transform: float4x4, dimensions: SIMD3<Float>) -> Path3D {
        let center = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let right = SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
        let up = SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
        let forward = SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)

        let halfWidth = dimensions.x / 2
        let halfHeight = dimensions.y / 2
        let halfDepth = dimensions.z / 2

        let rw = right * halfWidth
        let rh = up * halfHeight
        let rd = forward * halfDepth

        // Calculate the 8 corners of the box
        let c0 = center - rw - rh - rd
        let c1 = center + rw - rh - rd
        let c2 = center + rw + rh - rd
        let c3 = center - rw + rh - rd
        let c4 = center - rw - rh + rd
        let c5 = center + rw - rh + rd
        let c6 = center + rw + rh + rd
        let c7 = center - rw + rh + rd

        return Path3D { path in
            // Draw front face
            path.move(to: c0)
            path.addLine(to: c1)
            path.addLine(to: c2)
            path.addLine(to: c3)
            path.closeSubpath()

            // Draw back face
            path.move(to: c4)
            path.addLine(to: c5)
            path.addLine(to: c6)
            path.addLine(to: c7)
            path.closeSubpath()

            // Draw connecting edges
            path.move(to: c0)
            path.addLine(to: c4)
            path.move(to: c1)
            path.addLine(to: c5)
            path.move(to: c2)
            path.addLine(to: c6)
            path.move(to: c3)
            path.addLine(to: c7)
        }
    }

    private func createTexturesFromImageData(_ imageData: CameraImageData, device: MTLDevice) -> (textureY: MTLTexture, textureCbCr: MTLTexture)? {
        // Create Y plane texture
        let textureDescriptorY = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: imageData.widthY,
            height: imageData.heightY,
            mipmapped: false
        )
        textureDescriptorY.usage = [.shaderRead]

        guard let textureY = device.makeTexture(descriptor: textureDescriptorY) else {
            return nil
        }

        imageData.planeYData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            let region = MTLRegionMake2D(0, 0, imageData.widthY, imageData.heightY)
            textureY.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: imageData.widthY)
        }

        // Create CbCr plane texture
        let textureDescriptorCbCr = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Unorm,
            width: imageData.widthCbCr,
            height: imageData.heightCbCr,
            mipmapped: false
        )
        textureDescriptorCbCr.usage = [.shaderRead]

        guard let textureCbCr = device.makeTexture(descriptor: textureDescriptorCbCr) else {
            return nil
        }

        imageData.planeCbCrData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            let region = MTLRegionMake2D(0, 0, imageData.widthCbCr, imageData.heightCbCr)
            textureCbCr.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: imageData.widthCbCr * 2)
        }

        textureY.label = "Photo Quad Y"
        textureCbCr.label = "Photo Quad CbCr"

        return (textureY: textureY, textureCbCr: textureCbCr)
    }
}
