import CoreGraphics
import ImageIO
import Metal
import MetalKit
import ModelIO
internal import os
import simd
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Logging

internal let logger: Logger? = {
    guard ProcessInfo.processInfo.environment["LOGGING"] != nil else {
        return nil
    }
    return Logger(subsystem: "io.schwa.ultraviolence.examples", category: "default")
}()

#if canImport(AppKit)
public extension URL {
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([self])
    }
}
#endif

public extension SIMD4<Float> {
    init(color: Color) {
        let resolved = color.resolve(in: .init())
        self = [
            Float(resolved.linearRed),
            Float(resolved.linearGreen),
            Float(resolved.linearBlue),
            Float(resolved.opacity)
        ]
    }
}

extension Color {
    // TODO: Not linear
    var float4: SIMD4<Float> {
        get {
            let resolved = self.resolve(in: .init())
            return [Float(resolved.red), Float(resolved.green), Float(resolved.blue), Float(resolved.opacity)]
        }
        set {
            self = Color(red: Double(newValue[0]), green: Double(newValue[1]), blue: Double(newValue[2]), opacity: Double(newValue[3]))
        }
    }
}

extension SIMD4<Float> {
    private var color: Color {
        get {
            // Construct a SwiftUI Color from the SIMD components
            Color(red: Double(self.x), green: Double(self.y), blue: Double(self.z), opacity: Double(self.w))
        }
        set {
            let resolved = newValue.resolve(in: .init())
            self = [Float(resolved.red), Float(resolved.green), Float(resolved.blue), Float(resolved.opacity)]
        }
    }
}

extension SIMD3<Float> {
    // TODO: Not linear
    private var color: Color {
        get {
            Color(red: Double(self.x), green: Double(self.y), blue: Double(self.z))
        }
        set {
            let resolved = newValue.resolve(in: .init())
            self = [Float(resolved.red), Float(resolved.green), Float(resolved.blue)]
        }
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

public func lookAtMatrix(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let forward = normalize(target - eye)
    let right = normalize(cross(forward, up))
    let newUp = cross(right, forward)

    return float4x4(
        SIMD4<Float>(right.x, right.y, right.z, 0),
        SIMD4<Float>(newUp.x, newUp.y, newUp.z, 0),
        SIMD4<Float>(forward.x, forward.y, forward.z, 0), // FIXED: Do NOT negate forward
        SIMD4<Float>(-dot(right, eye), -dot(newUp, eye), -dot(forward, eye), 1) // FIXED: Negate forward dot product
    )
}

extension View {
    @ViewBuilder
    func modifier(enabled: Bool, _ modifier: (some ViewModifier)) -> some View {
        if enabled {
            self.modifier(modifier)
        }
        else {
            self
        }
    }
}

// MARK: - Metal Extensions

extension MTLVertexFormat {
    var size: Int {
        switch self {
        case .invalid:
            fatalError("Invalid vertex format")
        case .uchar2:
            return MemoryLayout<UInt8>.size * 2
        case .uchar3:
            return MemoryLayout<UInt8>.size * 3
        case .uchar4:
            return MemoryLayout<UInt8>.size * 4
        case .char2:
            return MemoryLayout<Int8>.size * 2
        case .char3:
            return MemoryLayout<Int8>.size * 3
        case .char4:
            return MemoryLayout<Int8>.size * 4
        case .uchar2Normalized:
            return MemoryLayout<UInt8>.size * 2
        case .uchar3Normalized:
            return MemoryLayout<UInt8>.size * 3
        case .uchar4Normalized:
            return MemoryLayout<UInt8>.size * 4
        case .char2Normalized:
            return MemoryLayout<Int8>.size * 2
        case .char3Normalized:
            return MemoryLayout<Int8>.size * 3
        case .char4Normalized:
            return MemoryLayout<Int8>.size * 4
        case .ushort2:
            return MemoryLayout<UInt16>.size * 2
        case .ushort3:
            return MemoryLayout<UInt16>.size * 3
        case .ushort4:
            return MemoryLayout<UInt16>.size * 4
        case .short2:
            return MemoryLayout<Int16>.size * 2
        case .short3:
            return MemoryLayout<Int16>.size * 3
        case .short4:
            return MemoryLayout<Int16>.size * 4
        case .ushort2Normalized:
            return MemoryLayout<UInt16>.size * 2
        case .ushort3Normalized:
            return MemoryLayout<UInt16>.size * 3
        case .ushort4Normalized:
            return MemoryLayout<UInt16>.size * 4
        case .short2Normalized:
            return MemoryLayout<Int16>.size * 2
        case .short3Normalized:
            return MemoryLayout<Int16>.size * 3
        case .short4Normalized:
            return MemoryLayout<Int16>.size * 4
        case .half2:
            return MemoryLayout<Float16>.size * 2
        case .half3:
            return MemoryLayout<Float16>.size * 3
        case .half4:
            return MemoryLayout<Float16>.size * 4
        case .float:
            return MemoryLayout<Float>.size
        case .float2:
            return MemoryLayout<Float>.size * 2
        case .float3:
            return MemoryLayout<Float>.size * 3
        case .float4:
            return MemoryLayout<Float>.size * 4
        case .int:
            return MemoryLayout<Int32>.size
        case .int2:
            return MemoryLayout<Int32>.size * 2
        case .int3:
            return MemoryLayout<Int32>.size * 3
        case .int4:
            return MemoryLayout<Int32>.size * 4
        case .uint:
            return MemoryLayout<UInt32>.size
        case .uint2:
            return MemoryLayout<UInt32>.size * 2
        case .uint3:
            return MemoryLayout<UInt32>.size * 3
        case .uint4:
            return MemoryLayout<UInt32>.size * 4
        case .int1010102Normalized:
            return MemoryLayout<UInt32>.size
        case .uint1010102Normalized:
            return MemoryLayout<UInt32>.size
        case .uchar4Normalized_bgra:
            return MemoryLayout<UInt8>.size * 4
        case .uchar:
            return MemoryLayout<UInt8>.size
        case .char:
            return MemoryLayout<Int8>.size
        case .ucharNormalized:
            return MemoryLayout<UInt8>.size
        case .charNormalized:
            return MemoryLayout<Int8>.size
        case .ushort:
            return MemoryLayout<UInt16>.size
        case .short:
            return MemoryLayout<Int16>.size
        case .ushortNormalized:
            return MemoryLayout<UInt16>.size
        case .shortNormalized:
            return MemoryLayout<Int16>.size
        case .half:
            return MemoryLayout<Float16>.size
        case .floatRG11B10:
            return MemoryLayout<UInt32>.size
        case .floatRGB9E5:
            return MemoryLayout<UInt32>.size
        @unknown default:
            fatalError("Unknown vertex format")
        }
    }
}

extension MTLVertexFormat: @retroactive CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .invalid:
            return "invalid"
        case .uchar2:
            return "uchar2"
        case .uchar3:
            return "uchar3"
        case .uchar4:
            return "uchar4"
        case .char2:
            return "char2"
        case .char3:
            return "char3"
        case .char4:
            return "char4"
        case .uchar2Normalized:
            return "uchar2Normalized"
        case .uchar3Normalized:
            return "uchar3Normalized"
        case .uchar4Normalized:
            return "uchar4Normalized"
        case .char2Normalized:
            return "char2Normalized"
        case .char3Normalized:
            return "char3Normalized"
        case .char4Normalized:
            return "char4Normalized"
        case .ushort2:
            return "ushort2"
        case .ushort3:
            return "ushort3"
        case .ushort4:
            return "ushort4"
        case .short2:
            return "short2"
        case .short3:
            return "short3"
        case .short4:
            return "short4"
        case .ushort2Normalized:
            return "ushort2Normalized"
        case .ushort3Normalized:
            return "ushort3Normalized"
        case .ushort4Normalized:
            return "ushort4Normalized"
        case .short2Normalized:
            return "short2Normalized"
        case .short3Normalized:
            return "short3Normalized"
        case .short4Normalized:
            return "short4Normalized"
        case .half2:
            return "half2"
        case .half3:
            return "half3"
        case .half4:
            return "half4"
        case .float:
            return "float"
        case .float2:
            return "float2"
        case .float3:
            return "float3"
        case .float4:
            return "float4"
        case .int:
            return "int"
        case .int2:
            return "int2"
        case .int3:
            return "int3"
        case .int4:
            return "int4"
        case .uint:
            return "uint"
        case .uint2:
            return "uint2"
        case .uint3:
            return "uint3"
        case .uint4:
            return "uint4"
        case .int1010102Normalized:
            return "int1010102Normalized"
        case .uint1010102Normalized:
            return "uint1010102Normalized"
        case .uchar4Normalized_bgra:
            return "uchar4Normalized_bgra"
        case .uchar:
            return "uchar"
        case .char:
            return "char"
        case .ucharNormalized:
            return "ucharNormalized"
        case .charNormalized:
            return "charNormalized"
        case .ushort:
            return "ushort"
        case .short:
            return "short"
        case .ushortNormalized:
            return "ushortNormalized"
        case .shortNormalized:
            return "shortNormalized"
        case .half:
            return "half"
        case .floatRG11B10:
            return "floatRG11B10"
        case .floatRGB9E5:
            return "floatRGB9E5"
        @unknown default:
            return "unknown"
        }
    }
}

extension MTLVertexStepFunction: @retroactive CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .constant:
            return "constant"
        case .perVertex:
            return "perVertex"
        case .perInstance:
            return "perInstance"
        case .perPatch:
            return "perPatch"
        case .perPatchControlPoint:
            return "perPatchControlPoint"
        @unknown default:
            return "unknown"
        }
    }
}
