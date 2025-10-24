#if os(iOS)
import ARKit
import CoreVideo
import GeometryLite3D
import Metal
import MetalKit
import Network
import Observation
import RoomPlan
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport
import UltraviolenceUI

public struct CaptureDemoView: View {
    @State
    private var viewModel = CaptureDemoViewModel()

    @State
    private var showMeshes = false

    @State
    private var showPlanes = false

    @State
    private var limitAnchors = false

    @State
    private var client: NetworkClient?

    @State
    private var isClientConnected = false

    @State
    private var serviceType = "_ultraviolence._tcp"

    @State
    private var showStats = false

    @State
    private var showSettings = false

    @State
    private var sendFrameData = true

    @State
    private var sendAnchors = true

    @State
    private var sendRoomData = true

    @State
    private var sendCameraImages = false

    let teapot: MTKMesh
    let environmentTexture: MTLTexture

    public init() {
        teapot = (MTKMesh.teapot(options: [.generateTangentBasis, .generateTextureCoordinatesIfMissing, .useSimpleTextureCoordinates]))
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
        _ = {
            viewModel.sendFrameData = sendFrameData
            viewModel.sendAnchors = sendAnchors
            viewModel.sendRoomData = sendRoomData
            viewModel.sendCameraImages = sendCameraImages
        }()

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

                        let planeAnchors = currentFrame.anchors.compactMap { $0 as? ARPlaneAnchor }
                        ARAnchorsRenderPipeline(
                            cameraMatrix: viewMatrix,
                            projectionMatrix: projectionMatrix,
                            viewport: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
                            meshAnchors: viewModel.meshAnchors,
                            planeAnchors: planeAnchors,
                            showMeshes: showMeshes,
                            showPlanes: showPlanes,
                            limitAnchors: limitAnchors
                        )

                        try AxisLinesRenderPipeline(
                            mvpMatrix: viewProjectionMatrix,
                            viewMatrix: viewMatrix,
                            projectionMatrix: projectionMatrix,
                            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
                            lineWidth: 2.0
                        )
                    }
                }
            }
            .metalDepthStencilPixelFormat(.depth32Float)
            .metalClearColor(.init(red: 0, green: 0, blue: 0, alpha: 0))
        }
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea()
        .overlay {
            ARCoachingOverlayAdaptor(session: viewModel.session)
        }
        .toolbar {
            Toggle(isOn: $showStats) {
                Label("Stats", systemImage: "chart.bar")
            }

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Toggle(isOn: $isClientConnected) {
                Label("Network", systemImage: isClientConnected ? "network" : "network.slash")
            }
            .onChange(of: isClientConnected) { _, newValue in
                if newValue {
                    connectClient()
                } else {
                    disconnectClient()
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("Display") {
                        Toggle("Show Meshes", isOn: $showMeshes)
                        Toggle("Show Planes", isOn: $showPlanes)
                        Toggle("Limit to First", isOn: $limitAnchors)
                    }

                    Section("Network Transmission") {
                        Toggle("Send Frame Data", isOn: $sendFrameData)
                        Toggle("Send Anchors", isOn: $sendAnchors)
                        Toggle("Send RoomPlan Data", isOn: $sendRoomData)
                        Toggle("Send Camera Images", isOn: $sendCameraImages)
                            .foregroundStyle(sendCameraImages ? .orange : .primary)
                        if sendCameraImages {
                            Text("⚠️ High bandwidth")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Section("RoomPlan") {
                        Button(viewModel.isRoomCaptureActive ? "Stop Capture" : "Start Capture") {
                            if viewModel.isRoomCaptureActive {
                                viewModel.stopRoomCapture()
                            } else {
                                viewModel.startRoomCapture()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showSettings = false
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showStats {
                ARStatsView(viewModel: viewModel, isClientConnected: isClientConnected, serviceType: serviceType)
            }
        }
    }

    private func connectClient() {
        guard client == nil else {
            return
        }

        Task {
            do {
                let newClient = NetworkClient()

                await newClient.addChannel("frame")
                await newClient.addChannel("camera_image")
                try await newClient.connect(type: serviceType) {
                    Task { @MainActor in
                        viewModel.isClientConnected = true
                        viewModel.networkClient = newClient
                    }
                }

                await MainActor.run {
                    client = newClient
                    isClientConnected = true
                }
            } catch {
                logger?.error("Connection failed: \(error.localizedDescription)")
                await MainActor.run {
                    isClientConnected = false
                }
            }
        }
    }

    private func disconnectClient() {
        guard client != nil else {
            return
        }

        Task {
            await client?.disconnect()
            await MainActor.run {
                client = nil
                viewModel.isClientConnected = false
                viewModel.networkClient = nil
            }
        }
    }
}

// MARK: - AR Stats View

private struct ARStatsView: View {
    let viewModel: CaptureDemoViewModel
    let isClientConnected: Bool
    let serviceType: String

    var body: some View {
        if let cameraTrackingState = viewModel.cameraTrackingState, let currentFrame = viewModel.currentFrame {
            let meshAnchors = currentFrame.anchors.compactMap { $0 as? ARMeshAnchor }
            let planeAnchors = currentFrame.anchors.compactMap { $0 as? ARPlaneAnchor }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    LabeledContent("Network") {
                        HStack(spacing: 4) {
                            Image(systemName: isClientConnected ? "network" : "network.slash")
                                .foregroundStyle(isClientConnected ? .green : .red)
                                .accessibilityLabel(isClientConnected ? "Network connected" : "Network disconnected")
                            Text(isClientConnected ? "Connected" : "Disconnected")
                                .foregroundStyle(isClientConnected ? .green : .red)
                        }
                    }
                    LabeledContent("Service", value: serviceType)
                        .gridCellColumns(2)
                }
                GridRow {
                    LabeledContent("Tracking") {
                        Text(String(describing: cameraTrackingState))
                            .foregroundStyle(trackingStateColor(cameraTrackingState))
                    }
                    LabeledContent("Camera", value: "\(viewModel.currentTextureY?.width ?? 0)x\(viewModel.currentTextureY?.height ?? 0)")
                    LabeledContent("Anchors", value: currentFrame.anchors.count.formatted())
                }
                GridRow {
                    LabeledContent("Meshes", value: meshAnchors.count.formatted())
                    LabeledContent("Planes", value: planeAnchors.count.formatted())
                    if let firstMesh = meshAnchors.first {
                        LabeledContent("Vertices", value: firstMesh.geometry.vertices.count.formatted())
                    }
                }
                if let firstMesh = meshAnchors.first {
                    GridRow {
                        LabeledContent("Faces", value: firstMesh.geometry.faces.count.formatted())
                        if let room = viewModel.finalRoom {
                            LabeledContent("Walls", value: room.walls.count.formatted())
                            LabeledContent("Doors", value: room.doors.count.formatted())
                        } else if viewModel.isRoomCaptureActive {
                            LabeledContent("RoomPlan", value: "Capturing...")
                                .gridCellColumns(2)
                        }
                    }
                    if let room = viewModel.finalRoom {
                        GridRow {
                            LabeledContent("Windows", value: room.windows.count.formatted())
                            LabeledContent("Objects", value: room.objects.count.formatted())
                        }
                    }
                } else if let room = viewModel.finalRoom {
                    GridRow {
                        LabeledContent("Walls", value: room.walls.count.formatted())
                        LabeledContent("Doors", value: room.doors.count.formatted())
                        LabeledContent("Windows", value: room.windows.count.formatted())
                    }
                    GridRow {
                        LabeledContent("Objects", value: room.objects.count.formatted())
                    }
                } else if viewModel.isRoomCaptureActive {
                    GridRow {
                        LabeledContent("RoomPlan", value: "Capturing...")
                            .gridCellColumns(3)
                    }
                }
            }
            .labeledContentStyle(CompactStatStyle())
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
    }

    private func trackingStateColor(_ state: ARCamera.TrackingState) -> Color {
        switch state {
        case .normal:
            return .green
        case .limited:
            return .orange
        case .notAvailable:
            return .red
        }
    }
}

private struct CompactStatStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            configuration.label
                .font(.caption)
                .foregroundStyle(.secondary)
            configuration.content
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 100, alignment: .leading)
    }
}

#endif
