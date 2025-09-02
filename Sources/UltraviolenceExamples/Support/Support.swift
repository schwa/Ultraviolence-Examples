import CoreGraphics
import ImageIO
import Metal
import MetalKit
import ModelIO
import simd
import SwiftUI
import Ultraviolence
import UltraviolenceSupport
import UniformTypeIdentifiers

#if canImport(AppKit)
public extension URL {
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([self])
    }
}
#endif

public extension MTKMesh {
    convenience init(name: String, bundle: Bundle) throws {
        let device = _MTLCreateSystemDefaultDevice()
        let teapotURL = bundle.url(forResource: name, withExtension: "obj")
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.stride * 3, bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<Float>.stride * 6, bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.stride * 8)
        let mdlAsset = MDLAsset(url: teapotURL, vertexDescriptor: vertexDescriptor, bufferAllocator: MTKMeshBufferAllocator(device: device))
        let mdlMesh = (mdlAsset.object(at: 0) as? MDLMesh).orFatalError(.resourceCreationFailure("Failed to load teapot mesh."))
        try self.init(mesh: mdlMesh, device: device)
    }

    static func teapot() -> MTKMesh {
        do {
            return try MTKMesh(name: "teapot", bundle: .main)
        }
        catch {
            fatalError("\(error)")
        }
    }

    static func sphere(extent: SIMD3<Float> = [1, 1, 1], inwardNormals: Bool = false) -> MTKMesh {
        do {
            let device = _MTLCreateSystemDefaultDevice()
            let allocator = MTKMeshBufferAllocator(device: device)
            let mdlMesh = MDLMesh(sphereWithExtent: extent, segments: [48, 48], inwardNormals: inwardNormals, geometryType: .triangles, allocator: allocator)
            return try MTKMesh(mesh: mdlMesh, device: device)
        }
        catch {
            fatalError("\(error)")
        }
    }

    static func plane(width: Float = 1, height: Float = 1, segments: SIMD2<UInt32> = [2, 2]) -> MTKMesh {
        do {
            let device = _MTLCreateSystemDefaultDevice()
            let allocator = MTKMeshBufferAllocator(device: device)
            let mdlMesh = MDLMesh(planeWithExtent: [width, height, 0], segments: segments, geometryType: .triangles, allocator: allocator)
            return try MTKMesh(mesh: mdlMesh, device: device)
        }
        catch {
            fatalError("\(error)")
        }
    }
}

public extension simd_quatf {
    static var identity: simd_quatf {
        simd_quatf(angle: 0, axis: [0, 1, 0]) // No rotation
    }
}

public struct Packed3<Scalar> where Scalar: SIMDScalar {
    public var x: Scalar
    public var y: Scalar
    public var z: Scalar

    public init(x: Scalar, y: Scalar, z: Scalar) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public extension Packed3 {
    subscript(i: Int) -> Scalar {
        get {
            switch i {
            case 0:
                return x
            case 1:
                return y
            case 2:
                return z
            default:
                fatalError("Index out of bounds.")
            }
        }
        set {
            switch i {
            case 0:
                x = newValue
            case 1:
                y = newValue
            case 2:
                z = newValue
            default:
                fatalError("Index out of bounds.")
            }
        }
    }
}

extension Packed3: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Scalar...) {
        x = elements[0]
        y = elements[1]
        z = elements[2]
    }
}

extension Packed3: Sendable where Scalar: Sendable {
}

extension Packed3: Equatable where Scalar: Equatable {
}

public extension Packed3 where Scalar: Numeric {
    // TODO: #137 Flesh this out.
    static func *(lhs: Self, rhs: Scalar) -> Self {
        Self(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }
}

public extension Packed3 {
    init(_ other: Packed3<Scalar>) {
        self = other
    }
    init(_ other: SIMD3<Scalar>) {
        self.init(x: other.x, y: other.y, z: other.z)
    }
}

#if os(iOS) || (os(macOS) && !arch(x86_64))
public extension Packed3 where Scalar == Float {
    init(_ other: Packed3<Float16>) {
        self.init(x: Float(other.x), y: Float(other.y), z: Float(other.z))
    }
}

public extension Packed3 where Scalar == Float16 {
    init(_ other: Packed3<Float>) {
        self.init(x: Float16(other.x), y: Float16(other.y), z: Float16(other.z))
    }
    init(_ other: SIMD3<Float>) {
        self.init(x: Float16(other.x), y: Float16(other.y), z: Float16(other.z))
    }
}
#endif // os(iOS) || (os(macOS) && !arch(x86_64))

public extension SIMD3 {
    init(_ packed: Packed3<Scalar>) {
        self.init(packed.x, packed.y, packed.z)
    }
}

public extension Draw {
    init(mtkMesh: MTKMesh) {
        self.init { encoder in
            encoder.setVertexBuffers(of: mtkMesh)
            encoder.draw(mtkMesh)
        }
    }
}

public extension MTLDevice {
    func makeTexture(name: String, bundle: Bundle? = nil) throws -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: self)
        return try textureLoader.newTexture(name: name, scaleFactor: 1.0, bundle: bundle)
    }
}

public extension SIMD4<Float> {
    init(color: Color) {
        let resolved = color.resolve(in: .init())
        self = [
            Float(resolved.linearRed),
            Float(resolved.linearGreen),
            Float(resolved.linearBlue),
            Float(1.0) // TODO:
        ]
    }
}

public  struct BoundingBox {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }
}

public extension MTLDevice {
    @MainActor
    func makeTexture(content: some View) throws -> MTLTexture {
        var cgImage: CGImage?
        let renderer = ImageRenderer(content: content)
        renderer.render { size, callback in
            guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return
            }
            callback(context)
            cgImage = context.makeImage()
        }
        let textureLoader = MTKTextureLoader(device: self)
        guard let cgImage else {
            throw UltraviolenceError.generic("Failed to create image.")
        }
        return try textureLoader.newTexture(cgImage: cgImage, options: [
            .textureUsage: MTLTextureUsage([.shaderRead, .shaderWrite]).rawValue,
            .SRGB: false
        ])
    }

    @MainActor
    func makeTextureCubeFromCrossTexture(texture: MTLTexture) throws -> MTLTexture {
        // Convert a skybox texture stored as a "cross" shape in a 2d texture into a texture cube:
        //     [5]
        // [1] [4] [0] [5]
        //     [2]
        let size = SIMD2<Int>(texture.width / 4, texture.height / 3)
        let cellWidth = texture.width / 4
        let cellHeight = texture.height / 3
        let cubeMapDescriptor = MTLTextureDescriptor()
        cubeMapDescriptor.textureType = .typeCube
        cubeMapDescriptor.pixelFormat = texture.pixelFormat
        cubeMapDescriptor.width = size.x
        cubeMapDescriptor.height = size.y
        guard let cubeMap = makeTexture(descriptor: cubeMapDescriptor) else {
            throw UltraviolenceError.generic("Failed to create texture cube.")
        }
        let blit = try BlitPass {
            Blit { encoder in
                let origins: [SIMD2<Int>] = [
                    [2, 1], [0, 1], [1, 0], [1, 2], [1, 1], [3, 1]
                ]
                for (slice, origin) in origins.enumerated() {
                    let origin = SIMD2<Int>(origin.x * cellWidth, origin.y * cellHeight)
                    encoder.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: origin.x, y: origin.y, z: 0), sourceSize: .init(width: size.x, height: size.y, depth: 1), to: cubeMap, destinationSlice: slice, destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
                }
            }
        }
        try blit.run()
        return cubeMap
    }
}

public func clamp<T>(_ value: T, to range: ClosedRange<T>) -> T where T: Comparable {
    min(max(value, range.lowerBound), range.upperBound)
}

public extension FloatingPoint {
    func clamped(to range: ClosedRange<Self>) -> Self {
        clamp(self, to: range)
    }
}

public func wrap(_ value: Double, to range: ClosedRange<Double>) -> Double {
    let size = range.upperBound - range.lowerBound
    let normalized = value - range.lowerBound
    return (normalized.truncatingRemainder(dividingBy: size) + size).truncatingRemainder(dividingBy: size) + range.lowerBound
}

public extension FloatingPoint {
    func wrapped(to range: ClosedRange<Self>) -> Self {
        let rangeSize = range.upperBound - range.lowerBound
        let wrappedValue = (self - range.lowerBound).truncatingRemainder(dividingBy: rangeSize)
        return (wrappedValue < 0 ? wrappedValue + rangeSize : wrappedValue) + range.lowerBound
    }
}

public extension ClosedRange where Bound == Angle {
    var degrees: ClosedRange<Double> {
        lowerBound.degrees ... upperBound.degrees
    }
}

struct PopoverButton <Label, Content>: View where Label: View, Content: View {
    var label: () -> Label
    var content: () -> Content

    @State
    private var isPopoverPresented: Bool = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        }
        label: {
            label()
        }
        .popover(isPresented: $isPopoverPresented) {
            content()
        }
    }
}

extension PopoverButton where Label == SwiftUI.Label<Text, Image> {
    init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(label: { SwiftUI.Label(titleKey, systemImage: systemImage) }, content: content)
    }
}

struct URLPicker <Label>: View where Label: View {
    var label: Label
    var urls: [URL]
    var action: (URL) -> Void

    init(label: () -> Label, urls: [URL], action: @escaping (URL) -> Void) {
        self.label = label()
        self.urls = urls
        self.action = action
    }

    var body: some View {
        #if os(macOS)
        MenuButton(label: label) {
            ForEach(urls, id: \.self) { url in
                Button(url.lastPathComponent) {
                    action(url)
                }
            }
        }
        #endif
    }
}

extension URLPicker {
    init(label: () -> Label, rootURL: URL, utiTypes: [UTType], action: @escaping (URL) -> Void) {
        let urls = (FileManager().enumerator(at: rootURL, includingPropertiesForKeys: [.contentTypeKey])?.compactMap { $0 as? URL } ?? [])
            .filter { url in
                guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
                    return false
                }
                return utiTypes.contains { contentType.conforms(to: $0) }
            }
        self.init(label: label, urls: urls, action: action)
    }
}

extension URLPicker where Label == Text {
    init(title titleKey: LocalizedStringKey, rootURL: URL, utiTypes: [UTType], action: @escaping (URL) -> Void) {
        self.init(label: { Text(titleKey) }, rootURL: rootURL, utiTypes: utiTypes, action: action)
    }
}
