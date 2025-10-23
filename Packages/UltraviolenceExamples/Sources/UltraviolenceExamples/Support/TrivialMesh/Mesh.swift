import GeometryLite3D
import Metal
import simd
import UltraviolenceSupport

struct Mesh {
    var label: String?
    var submeshes: [Submesh]
    var vertexDescriptor: VertexDescriptor
    var vertexBuffers: [Buffer]

    struct Submesh {
        var label: String?
        var primitiveType: MTLPrimitiveType
        var indices: Buffer
    }

    struct Buffer {
        var buffer: MTLBuffer
        var count: Int
        var offset: Int
    }

    init(label: String? = nil, submeshes: [Submesh], vertexDescriptor: VertexDescriptor, vertexBuffers: [Buffer]) {
        self.label = label
        self.submeshes = submeshes
        self.vertexDescriptor = vertexDescriptor
        self.vertexBuffers = vertexBuffers
    }
}

extension MTLRenderCommandEncoder {
    func draw(mesh: Mesh) {
        // TODO: Simple case
        assert(mesh.vertexBuffers.count == 1)
        setVertexBuffer(mesh.vertexBuffers[0].buffer, offset: mesh.vertexBuffers[0].offset, index: 0) // TODO: Index
        for submesh in mesh.submeshes {
            drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indices.count, indexType: .uint32, indexBuffer: submesh.indices.buffer, indexBufferOffset: submesh.indices.offset)
        }
    }
}

// MARK: - Codable

extension Mesh.Buffer: Codable {
    enum CodingKeys: String, CodingKey {
        case bufferData
        case count
        case offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bufferData = try container.decode(Data.self, forKey: .bufferData)
        count = try container.decode(Int.self, forKey: .count)
        offset = try container.decode(Int.self, forKey: .offset)

        // Recreate the buffer from the decoded data
        let device = _MTLCreateSystemDefaultDevice()

        guard let recreatedBuffer = device.makeBuffer(bytes: (bufferData as NSData).bytes, length: bufferData.count, options: []) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Failed to create Metal buffer from data"
                )
            )
        }

        buffer = recreatedBuffer
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Extract data from MTLBuffer
        let bufferPointer = buffer.contents()
        let bufferData = Data(bytes: bufferPointer, count: buffer.length)

        try container.encode(bufferData, forKey: .bufferData)
        try container.encode(count, forKey: .count)
        try container.encode(offset, forKey: .offset)
    }
}

extension Mesh.Submesh: Codable {
    enum CodingKeys: String, CodingKey {
        case label
        case primitiveType
        case indices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        let primitiveTypeRawValue = try container.decode(UInt.self, forKey: .primitiveType)
        primitiveType = MTLPrimitiveType(rawValue: primitiveTypeRawValue) ?? .triangle
        indices = try container.decode(Mesh.Buffer.self, forKey: .indices)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(primitiveType.rawValue, forKey: .primitiveType)
        try container.encode(indices, forKey: .indices)
    }
}

extension Mesh: Codable {
    enum CodingKeys: String, CodingKey {
        case label
        case submeshes
        case vertexDescriptor
        case vertexBuffers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        submeshes = try container.decode([Submesh].self, forKey: .submeshes)
        vertexDescriptor = try container.decode(VertexDescriptor.self, forKey: .vertexDescriptor)
        vertexBuffers = try container.decode([Buffer].self, forKey: .vertexBuffers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(submeshes, forKey: .submeshes)
        try container.encode(vertexDescriptor, forKey: .vertexDescriptor)
        try container.encode(vertexBuffers, forKey: .vertexBuffers)
    }
}
