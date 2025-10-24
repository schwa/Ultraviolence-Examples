import CBORCoding
import Foundation
import Network

// MARK: - NetworkCBOREncoder

public struct NetworkCBOREncoder: NetworkEncoder, Sendable {
    public init() {
        // Default initializer
    }

    public func encode<T>(_ value: T) throws -> Data where T: Encodable {
        try CBOREncoder().encode(value)
    }
}

// MARK: - NetworkCBORDecoder

public struct NetworkCBORDecoder: NetworkDecoder, Sendable {
    public init() {
        // Default initializer
    }

    public func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable {
        try CBORDecoder().decode(type, from: data)
    }
}

// MARK: - NetworkCBORCoder

public struct NetworkCBORCoder: NetworkCoder, Sendable {
    public typealias Encoder = NetworkCBOREncoder
    public typealias Decoder = NetworkCBORDecoder

    public init() {
        // Default initializer
    }

    public func makeEncoder() -> NetworkCBOREncoder {
        NetworkCBOREncoder()
    }

    public func makeDecoder() -> NetworkCBORDecoder {
        NetworkCBORDecoder()
    }
}
