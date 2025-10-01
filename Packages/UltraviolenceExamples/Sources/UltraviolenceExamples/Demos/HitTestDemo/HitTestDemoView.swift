import GeometryLite3D
import Metal
import MetalKit
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceExampleShaders
import UltraviolenceSupport
import UltraviolenceUI

enum HitTestVisualizationMode: String, CaseIterable {
    case none = "None"
    case geometryID = "Geometry ID"
    case instanceID = "Instance ID"
    case triangleID = "Triangle ID"
    case depth = "Depth"
    case triangleCoordinates = "Triangle Coords"
}

public struct HitTestDemoView: View {
    @State
    private var mesh = MTKMesh.teapot().relabeled("teapot")
    @State
    private var modelMatrix: float4x4 = .identity
    @State
    private var material = BlinnPhongMaterial(
        ambient: .color([0.2, 0.2, 0.2]),
        diffuse: .color([0.7, 0.3, 0.3]),
        specular: .color([1.0, 1.0, 1.0]),
        shininess: 32
    )
    @State
    private var lighting: Lighting
    @State
    private var skyboxTexture: MTLTexture
    @State
    private var projection: any ProjectionProtocol = PerspectiveProjection()
    @State
    private var cameraMatrix: simd_float4x4 = .init(translation: [0, 2, 6])
    @State
    private var hitTestTextures: HitTestTextures?
    @State
    private var lastHitResult: HitTestResult?
    @State
    private var drawableSize: CGSize = .zero
    @State
    private var visualizationMode: HitTestVisualizationMode = .none
    @State
    private var renderViewSize: CGSize = .zero

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    public init() {
        self.lighting = try! .demo()
        let device = _MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device.makeCommandQueue().orFatalError("Failed to create command queue")
        self.skyboxTexture = try! device.makeTextureCubeFromCrossTexture(texture: try! device.makeTexture(name: "Skybox", bundle: .main))
    }

    public var body: some View {
        ZStack {
            WorldView(projection: $projection, cameraMatrix: $cameraMatrix, targetMatrix: .constant(nil)) {
                TimelineView(.animation) { timeline in
                    // swiftlint:disable:next accessibility_trait_for_button
                    RenderView { _, drawableSize in
                        let projectionMatrix = projection.projectionMatrix(for: drawableSize)
                        // Main rendering pass
                        try RenderPass {
                            // Render teapot with Blinn-Phong shading
                            try BlinnPhongShader {
                                try Draw { encoder in
                                    encoder.setVertexBuffers(of: mesh)
                                    encoder.draw(mesh)
                                }
                                .blinnPhongMaterial(material)
                                .transforms(.init(modelMatrix: modelMatrix, cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix))
                                .lighting(lighting)
                            }
                            .vertexDescriptor(mesh.vertexDescriptor)
                            .depthCompare(function: .less, enabled: true)
                        }

                        // Hit test rendering pass (to offscreen textures)
                        if let textures = hitTestTextures {
                            try RenderPass {
                                try HitTestShader {
                                    Draw { encoder in
                                        encoder.setVertexBuffers(of: mesh)
                                        encoder.draw(mesh)
                                    }
                                    .transforms(.init(modelMatrix: modelMatrix, cameraMatrix: cameraMatrix, projectionMatrix: projectionMatrix))
                                    .geometryID(0)
                                }
                                .vertexDescriptor(mesh.vertexDescriptor)
                                .depthCompare(function: .less, enabled: true)
                            }
                            .renderPassDescriptorModifier { descriptor in
                                descriptor.colorAttachments[0].texture = textures.geometryIDTexture
                                descriptor.colorAttachments[0].loadAction = .clear
                                descriptor.colorAttachments[0].clearColor = MTLClearColor(red: -1, green: 0, blue: 0, alpha: 0)
                                descriptor.colorAttachments[0].storeAction = .store

                                descriptor.colorAttachments[1].texture = textures.instanceIDTexture
                                descriptor.colorAttachments[1].loadAction = .clear
                                descriptor.colorAttachments[1].clearColor = MTLClearColor(red: -1, green: 0, blue: 0, alpha: 0)
                                descriptor.colorAttachments[1].storeAction = .store

                                descriptor.colorAttachments[2].texture = textures.triangleIDTexture
                                descriptor.colorAttachments[2].loadAction = .clear
                                descriptor.colorAttachments[2].clearColor = MTLClearColor(red: -1, green: 0, blue: 0, alpha: 0)
                                descriptor.colorAttachments[2].storeAction = .store

                                descriptor.colorAttachments[3].texture = textures.depthTexture
                                descriptor.colorAttachments[3].loadAction = .clear
                                descriptor.colorAttachments[3].clearColor = MTLClearColor(red: 1.0, green: 0, blue: 0, alpha: 0)
                                descriptor.colorAttachments[3].storeAction = .store

                                descriptor.colorAttachments[4].texture = textures.triangleCoordinatesTexture
                                descriptor.colorAttachments[4].loadAction = .clear
                                descriptor.colorAttachments[4].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                                descriptor.colorAttachments[4].storeAction = .store

                                descriptor.depthAttachment.texture = textures.depthStencilTexture
                                descriptor.depthAttachment.loadAction = .clear
                                descriptor.depthAttachment.clearDepth = 1.0
                                descriptor.depthAttachment.storeAction = .dontCare
                            }
                        }

                        // Visualize the selected hit test texture if requested
                        if visualizationMode != .none, let textures = hitTestTextures {
                            let (sourceTexture, colorTransformName): (MTLTexture, String) = switch visualizationMode {
                            case .none:
                                fatalError("Should not reach here")
                            case .geometryID:
                                (textures.geometryIDTexture, "colorTransformHitTestVisualize")
                            case .instanceID:
                                (textures.instanceIDTexture, "colorTransformHitTestVisualize")
                            case .triangleID:
                                (textures.triangleIDTexture, "colorTransformHitTestVisualize")
                            case .depth:
                                (textures.depthTexture, "colorTransformDepthVisualize")
                            case .triangleCoordinates:
                                (textures.triangleCoordinatesTexture, "colorTransformIdentity")
                            }

                            try RenderPass {
                                try TextureBillboardPipeline(specifierA: .texture2D(sourceTexture), specifierB: .color([0, 0, 0]), colorTransformFunctionName: colorTransformName)
                            }
                        }
                    }
                    .coordinateSpace(name: "RenderView")
                    .frame(width: 512, height: 512)
                    .metalDepthStencilPixelFormat(.depth32Float)
                    .onDrawableSizeChange { size in
                        guard size.width > 0, size.height > 0 else {
                            return
                        }
                        drawableSize = size
                        hitTestTextures = HitTestTextures(device: device, size: size)
                    }
                    .onAppear {
                        if hitTestTextures == nil {
                            let size = CGSize(width: 1_920, height: 1_080) // Default size
                            drawableSize = size
                            hitTestTextures = HitTestTextures(device: device, size: size)
                        }
                    }
                    .onChange(of: timeline.date) {
                        //                    LightingAnimator.run(date: timeline.date, lighting: &lighting)
                        // Rotate the teapot
                        //                    modelMatrix = float4x4(yRotation: Float(timeline.date.timeIntervalSinceReferenceDate))
                    }
                    .onTapGesture(coordinateSpace: .named("RenderView")) { location in
                        performHitTest(at: location)
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            performHitTest(at: location)
                        case .ended:
                            break
                        }
                    }
                    .onGeometryChange(for: CGSize.self) { geometry in
                        geometry.size
                    } action: { newSize in
                        renderViewSize = newSize
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Visualization", selection: $visualizationMode) {
                    ForEach(HitTestVisualizationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }

            ToolbarItem {
                Button("Export Hit Grid") {
                    performFullGridHitTest()
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let result = lastHitResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location: (\(Int(result.location.x)), \(Int(result.location.y)))")
                    if result.geometryID != -1 {
                        Text("Geometry ID: \(result.geometryID)")
                        Text("Instance ID: \(result.instanceID)")
                        Text("Triangle ID: \(result.triangleID)")
                        Text("Depth: \(String(format: "%.3f", result.depth))")
                        Text("Barycentric: (\(String(format: "%.3f", result.triangleCoords.x)), \(String(format: "%.3f", result.triangleCoords.y)), \(String(format: "%.3f", result.triangleCoords.z)))")
                    }
                }
                .frame(width: 250)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding()
                .allowsHitTesting(false)
            } else {
                VStack {
                    Text("No Hit Test Result")
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(width: 250)
            }
        }
    }

    func performHitTest(at location: CGPoint) {
        guard let textures = hitTestTextures else {
            return
        }
        guard renderViewSize.width > 0, renderViewSize.height > 0 else {
            return
        }

        // Convert location from view coordinates to normalized [0...1] range
        // The location is in the RenderView's coordinate space
        let normalizedX = location.x / renderViewSize.width
        let normalizedY = location.y / renderViewSize.height

        // Convert normalized coordinates to texture pixel coordinates
        let metalX = Int(normalizedX * textures.size.width)
        let metalY = Int(normalizedY * textures.size.height)

        // Ensure coordinates are within texture bounds
        guard metalX >= 0, metalX < Int(textures.size.width), metalY >= 0, metalY < Int(textures.size.height) else {
            return
        }

        // Synchronize the buffers if needed on macOS
        #if os(macOS)
        if textures.geometryIDBuffer.storageMode == .managed {
            // Create a command buffer to synchronize managed buffers
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                return
            }
            blitEncoder.synchronize(resource: textures.geometryIDBuffer)
            blitEncoder.synchronize(resource: textures.instanceIDBuffer)
            blitEncoder.synchronize(resource: textures.triangleIDBuffer)
            blitEncoder.synchronize(resource: textures.depthBuffer)
            blitEncoder.synchronize(resource: textures.triangleCoordinatesBuffer)
            blitEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        #endif

        // Calculate the pixel offset in the buffer
        let bytesPerRow = textures.bytesPerRow
        let pixelOffset = metalY * (bytesPerRow / 4) + metalX // Divide by 4 since bytesPerRow is in bytes

        // Read directly from the buffers
        let geometryIDPtr = textures.geometryIDBuffer.contents().assumingMemoryBound(to: Int32.self)
        let geometryID = geometryIDPtr[pixelOffset]

        let instanceIDPtr = textures.instanceIDBuffer.contents().assumingMemoryBound(to: Int32.self)
        let instanceID = instanceIDPtr[pixelOffset]

        let triangleIDPtr = textures.triangleIDBuffer.contents().assumingMemoryBound(to: Int32.self)
        let triangleID = triangleIDPtr[pixelOffset]

        let depthPtr = textures.depthBuffer.contents().assumingMemoryBound(to: Float.self)
        let depth = depthPtr[pixelOffset]

        // For RGBA32Float texture, we need to account for 4 components per pixel
        let triangleCoordsOffset = pixelOffset * 4
        let coordsPtr = textures.triangleCoordinatesBuffer.contents().assumingMemoryBound(to: Float.self)
        let triangleCoords = SIMD3<Float>(coordsPtr[triangleCoordsOffset], coordsPtr[triangleCoordsOffset + 1], coordsPtr[triangleCoordsOffset + 2])

        // Store the result
        lastHitResult = HitTestResult(
            location: CGPoint(x: metalX, y: metalY),
            geometryID: geometryID,
            instanceID: instanceID,
            triangleID: triangleID,
            depth: depth,
            triangleCoords: triangleCoords
        )
    }

    func performFullGridHitTest() {
        guard let textures = hitTestTextures else {
            print("No hit test textures available")
            return
        }

        let width = Int(textures.size.width)
        let height = Int(textures.size.height)
        let bytesPerRow = textures.bytesPerRow

        print("Performing full grid hit test...")
        print("Texture size: \(width)x\(height)")

        // Synchronize buffers on macOS
        #if os(macOS)
        if textures.geometryIDBuffer.storageMode == .managed {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                return
            }
            blitEncoder.synchronize(resource: textures.geometryIDBuffer)
            blitEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        #endif

        // Read the geometry ID buffer
        let geometryIDPtr = textures.geometryIDBuffer.contents().assumingMemoryBound(to: Int32.self)

        // Create a grid of hit/no-hit values
        var hitGrid = Array(repeating: Array(repeating: false, count: width), count: height)
        var hitCount = 0
        var minY = Int.max
        var maxY = Int.min
        var minX = Int.max
        var maxX = Int.min

        // Sample every pixel
        for y in 0..<height {
            for x in 0..<width {
                let pixelOffset = y * (bytesPerRow / 4) + x
                let geometryID = geometryIDPtr[pixelOffset]

                // Check if we hit geometry (geometryID >= 0 means hit)
                let hit = geometryID >= 0
                hitGrid[y][x] = hit

                if hit {
                    hitCount += 1
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
            }
        }

        print("Hit test complete: \(hitCount) hits out of \(width * height) pixels")
        if hitCount > 0 {
            print("Hit bounds: X[\(minX)...\(maxX)], Y[\(minY)...\(maxY)]")
        }

        // Write PGM file
        writePGMFile(grid: hitGrid, width: width, height: height)
    }

    func writePGMFile(grid: [[Bool]], width: Int, height: Int) {
        // Create PGM content
        var pgmContent = "P2\n"  // ASCII grayscale format
        pgmContent += "\(width) \(height)\n"
        pgmContent += "255\n"  // Max gray value

        // Write pixel values (255 for hit, 0 for no hit)
        for y in 0..<height {
            for x in 0..<width {
                let value = grid[y][x] ? 255 : 0
                pgmContent += "\(value) "
            }
            pgmContent += "\n"
        }

        // Write to temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "hit_test_grid_\(timestamp).pgm"
        let filePath = tempDir.appendingPathComponent(filename).path

        do {
            try pgmContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            print("Wrote hit test grid to: \(filePath)")

            // Also create a smaller debug version showing just a sample
            if width > 100, height > 100 {
                // Sample every 10th pixel for a quick overview
                let sampleStep = 10
                var debugOutput = "Debug sample (every \(sampleStep)th pixel):\n"
                for y in stride(from: 0, to: min(height, 200), by: sampleStep) {
                    for x in stride(from: 0, to: min(width, 200), by: sampleStep) {
                        debugOutput += grid[y][x] ? "█" : "·"
                    }
                    debugOutput += "\n"
                }
                print(debugOutput)
            }
        } catch {
            print("Failed to write PGM file: \(error)")
        }
    }
}

struct HitTestResult {
    let location: CGPoint
    let geometryID: Int32
    let instanceID: Int32
    let triangleID: Int32
    let depth: Float
    let triangleCoords: SIMD3<Float>
}

struct HitTestTextures {
    let geometryIDTexture: MTLTexture
    let instanceIDTexture: MTLTexture
    let triangleIDTexture: MTLTexture
    let depthTexture: MTLTexture
    let triangleCoordinatesTexture: MTLTexture
    let depthStencilTexture: MTLTexture
    let geometryIDBuffer: MTLBuffer
    let instanceIDBuffer: MTLBuffer
    let triangleIDBuffer: MTLBuffer
    let depthBuffer: MTLBuffer
    let triangleCoordinatesBuffer: MTLBuffer
    let size: CGSize
    let bytesPerRow: Int

    init(device: MTLDevice, size: CGSize) {
        self.size = size
        let width = Int(size.width)
        let height = Int(size.height)

        // Calculate bytes per row with proper alignment (256 byte alignment is typical)
        let alignment = 256
        let bytesPerPixelR32 = 4 // r32Sint/r32Float
        let bytesPerPixelRGBA32F = 16 // rgba32Float
        self.bytesPerRow = ((width * bytesPerPixelR32 + alignment - 1) / alignment) * alignment
        let bytesPerRowRGBA = ((width * bytesPerPixelRGBA32F + alignment - 1) / alignment) * alignment

        // Create buffers for each texture
        let bufferLength = bytesPerRow * height
        let bufferLengthRGBA = bytesPerRowRGBA * height

        self.geometryIDBuffer = device.makeBuffer(length: bufferLength, options: []).orFatalError("Failed to create geometryID buffer")
        self.instanceIDBuffer = device.makeBuffer(length: bufferLength, options: []).orFatalError("Failed to create instanceID buffer")
        self.triangleIDBuffer = device.makeBuffer(length: bufferLength, options: []).orFatalError("Failed to create triangleID buffer")
        self.depthBuffer = device.makeBuffer(length: bufferLength, options: []).orFatalError("Failed to create depth buffer")
        self.triangleCoordinatesBuffer = device.makeBuffer(length: bufferLengthRGBA, options: []).orFatalError("Failed to create triangleCoordinates buffer")

        // Create texture descriptors
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.renderTarget, .shaderRead]

        // Create buffer-backed textures for r32Sint format
        textureDescriptor.pixelFormat = .r32Sint
        self.geometryIDTexture = geometryIDBuffer.makeTexture(descriptor: textureDescriptor, offset: 0, bytesPerRow: bytesPerRow).orFatalError("Failed to create geometryID texture")
        self.instanceIDTexture = instanceIDBuffer.makeTexture(descriptor: textureDescriptor, offset: 0, bytesPerRow: bytesPerRow).orFatalError("Failed to create instanceID texture")
        self.triangleIDTexture = triangleIDBuffer.makeTexture(descriptor: textureDescriptor, offset: 0, bytesPerRow: bytesPerRow).orFatalError("Failed to create triangleID texture")

        // Create buffer-backed texture for r32Float format
        textureDescriptor.pixelFormat = .r32Float
        self.depthTexture = depthBuffer.makeTexture(descriptor: textureDescriptor, offset: 0, bytesPerRow: bytesPerRow).orFatalError("Failed to create depth texture")

        // Create buffer-backed texture for rgba32Float format
        textureDescriptor.pixelFormat = .rgba32Float
        self.triangleCoordinatesTexture = triangleCoordinatesBuffer.makeTexture(descriptor: textureDescriptor, offset: 0, bytesPerRow: bytesPerRowRGBA).orFatalError("Failed to create triangleCoordinates texture")

        // Depth stencil texture cannot be buffer-backed, create normally
        textureDescriptor.pixelFormat = .depth32Float
        textureDescriptor.usage = .renderTarget
        self.depthStencilTexture = device.makeTexture(descriptor: textureDescriptor).orFatalError("Failed to create depthStencil texture")
    }
}
