import Collections
import Metal

struct VertexDescriptor: Equatable, Sendable {
    struct Attribute: Equatable, Sendable {
        enum Semantic: Equatable, Sendable, Codable {
            case unknown
            case position
            case normal
            case tangent
            case bitangent
            case texcoord
            case color
            case userDefined
        }

        var label: String?
        var semantic: Semantic
        var format: MTLVertexFormat
        var offset: Int
        var bufferIndex: Int
    }

    struct Layout: Equatable, Sendable {
        var bufferIndex: Int
        var stride: Int
        var stepFunction: MTLVertexStepFunction
        var stepRate: Int
    }

    var label: String?
    var attributes: [Attribute]
    var layouts: OrderedDictionary<Int, Layout>

    init(label: String? = nil, attributes: [Attribute], layouts: [Layout]) {
        self.label = label
        self.attributes = attributes
        self.layouts = .init(uniqueKeysWithValues: layouts.map { ($0.bufferIndex, $0) })
    }
}

extension VertexDescriptor: CustomDebugStringConvertible {
    var debugDescription: String {
        "VertexDescriptor(\(label.map { "label: \($0), " } ?? "")attributes: \(attributes), layouts: \(layouts))"
    }
}

extension VertexDescriptor.Attribute: CustomDebugStringConvertible {
    var debugDescription: String {
        "Attribute(\(label.map { "label: \($0), " } ?? "")semantic: \(semantic), format: \(format), offset: \(offset), bufferIndex: \(bufferIndex))"
    }
}

extension VertexDescriptor.Layout: CustomDebugStringConvertible {
    var debugDescription: String {
        "Layout(bufferIndex: \(bufferIndex), stride: \(stride), stepFunction: \(stepFunction), stepRate: \(stepRate))"
    }
}

extension VertexDescriptor.Layout {
    init(bufferIndex: Int) {
        self.init(bufferIndex: bufferIndex, stride: 0, stepFunction: .perVertex, stepRate: 1)
    }
}

extension VertexDescriptor {
    func dump() {
        print("VertexDescriptor: \(label ?? "nil")")
        print("Attributes:")
        for attribute in attributes {
            print("  - \(attribute)")
        }
        print("Layouts:")
        for layout in layouts.values {
            print("  - \(layout)")
        }
    }
}

extension VertexDescriptor {
    func normalized() -> Self {
        normalizingOffsets().normalizingStrides()
    }

    func normalizingOffsets() -> Self {
        var copy = self
        var offsetsPerBufferIndex: [Int: Int] = [:]
        copy.attributes = copy.attributes.map { attribute in
            let currentOffset = offsetsPerBufferIndex[attribute.bufferIndex, default: 0]
            var attribute = attribute
            attribute.offset = currentOffset
            offsetsPerBufferIndex[attribute.bufferIndex] = currentOffset + attribute.format.size
            return attribute
        }
        return copy
    }

    func normalizingStrides() -> Self {
        var copy = self
        for (bufferIndex, layout) in copy.layouts {
            let maxOffset = copy.attributes
                .filter { $0.bufferIndex == bufferIndex }
                .map { $0.offset + $0.format.size }
                .max() ?? 0
            var layout = layout
            layout.stride = maxOffset
            copy.layouts[bufferIndex] = layout
        }
        return copy
    }
}

extension VertexDescriptor {
    init(_ mtlVertexDescriptor: MTLVertexDescriptor) {
        var attributes: [Attribute] = []
        var layouts: [Layout] = []

        // Convert attributes
        for index in 0..<31 { // Metal supports up to 31 vertex attributes
            guard let mtlAttribute = mtlVertexDescriptor.attributes[index], mtlAttribute.format != .invalid else {
                continue
            }

            let attribute = Attribute(
                label: nil,
                semantic: .userDefined, // We can't infer semantic from MTLVertexDescriptor
                format: mtlAttribute.format,
                offset: mtlAttribute.offset,
                bufferIndex: mtlAttribute.bufferIndex
            )
            attributes.append(attribute)
        }

        // Convert layouts
        for bufferIndex in 0..<31 { // Metal supports up to 31 vertex buffer layouts
            guard let mtlLayout = mtlVertexDescriptor.layouts[bufferIndex], mtlLayout.stride > 0 else {
                continue
            }

            let layout = Layout(
                bufferIndex: bufferIndex,
                stride: mtlLayout.stride,
                stepFunction: mtlLayout.stepFunction,
                stepRate: mtlLayout.stepRate
            )
            layouts.append(layout)
        }

        self.init(label: nil, attributes: attributes, layouts: layouts)
    }

    var mtlVertexDescriptor: MTLVertexDescriptor {
        let mtlVertexDescriptor = MTLVertexDescriptor()
        for (index, attribute) in attributes.enumerated() {
            let mtlAttribute = mtlVertexDescriptor.attributes[index]
                .orFatalError("Missing MTL attribute descriptor at index \(index)")
            mtlAttribute.format = attribute.format
            mtlAttribute.offset = attribute.offset
            mtlAttribute.bufferIndex = attribute.bufferIndex
        }
        for (bufferIndex, layout) in layouts {
            let mtlLayout = mtlVertexDescriptor.layouts[bufferIndex]
                .orFatalError("Missing MTL layout descriptor at index \(bufferIndex)")
            mtlLayout.stride = layout.stride
            mtlLayout.stepFunction = layout.stepFunction
            mtlLayout.stepRate = layout.stepRate
        }
        return mtlVertexDescriptor
    }
}

extension MTLVertexDescriptor {
    convenience init(_ vertexDescriptor: VertexDescriptor) {
        self.init()

        // Set up attributes
        for (index, attribute) in vertexDescriptor.attributes.enumerated() {
            let mtlAttribute = attributes[index]
                .orFatalError("Missing MTL attribute descriptor at index \(index)")
            mtlAttribute.format = attribute.format
            mtlAttribute.offset = attribute.offset
            mtlAttribute.bufferIndex = attribute.bufferIndex
        }

        // Set up layouts
        for (bufferIndex, layout) in vertexDescriptor.layouts {
            let mtlLayout = layouts[bufferIndex]
                .orFatalError("Missing MTL layout descriptor at index \(bufferIndex)")
            mtlLayout.stride = layout.stride
            mtlLayout.stepFunction = layout.stepFunction
            mtlLayout.stepRate = layout.stepRate
        }
    }
}

// MARK: - Codable

extension VertexDescriptor.Attribute: Codable {
    enum CodingKeys: String, CodingKey {
        case label
        case semantic
        case format
        case offset
        case bufferIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        semantic = try container.decode(Semantic.self, forKey: .semantic)
        let formatRawValue = try container.decode(UInt.self, forKey: .format)
        format = MTLVertexFormat(rawValue: formatRawValue) ?? .invalid
        offset = try container.decode(Int.self, forKey: .offset)
        bufferIndex = try container.decode(Int.self, forKey: .bufferIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(semantic, forKey: .semantic)
        try container.encode(format.rawValue, forKey: .format)
        try container.encode(offset, forKey: .offset)
        try container.encode(bufferIndex, forKey: .bufferIndex)
    }
}

extension VertexDescriptor.Layout: Codable {
    enum CodingKeys: String, CodingKey {
        case bufferIndex
        case stride
        case stepFunction
        case stepRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bufferIndex = try container.decode(Int.self, forKey: .bufferIndex)
        stride = try container.decode(Int.self, forKey: .stride)
        let stepFunctionRawValue = try container.decode(UInt.self, forKey: .stepFunction)
        stepFunction = MTLVertexStepFunction(rawValue: stepFunctionRawValue) ?? .perVertex
        stepRate = try container.decode(Int.self, forKey: .stepRate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bufferIndex, forKey: .bufferIndex)
        try container.encode(stride, forKey: .stride)
        try container.encode(stepFunction.rawValue, forKey: .stepFunction)
        try container.encode(stepRate, forKey: .stepRate)
    }
}

extension VertexDescriptor: Codable {
    enum CodingKeys: String, CodingKey {
        case label
        case attributes
        case layouts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        attributes = try container.decode([Attribute].self, forKey: .attributes)
        let layoutsArray = try container.decode([Layout].self, forKey: .layouts)
        layouts = .init(uniqueKeysWithValues: layoutsArray.map { ($0.bufferIndex, $0) })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(attributes, forKey: .attributes)
        try container.encode(Array(layouts.values), forKey: .layouts)
    }
}
