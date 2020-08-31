import Foundation
import PersistentState
import Asn1Der


/// An ASN.1-DER coder
internal struct Asn1Coder: Coder {
    public static var `default`: Coder { Asn1Coder() }
    
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try DEREncoder().encode(value)
    }
    
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try DERDecoder().decode(type, from: data)
    }
}


// Convenience extensions for DER coding
internal extension Encodable {
    /// The DER encoded bytes of `self`
    ///
    ///  - Returns: The DER encoded bytes of `self`
    ///  - Throws: `DERError.unsupported` if value or a subfield is not supported by the encoder
    func derEncoded() throws -> Data {
        try Asn1Coder.default.encode(self)
    }
    /// The Base64 URL-safe DER encoded bytes of `self`
    ///
    ///  - Returns: The DER and then Base64Urlsafe encoded bytes of `self`
    ///  - Throws: `DERError.unsupported` if value or a subfield is not supported by the encoder
    func derEncodedUrlsafe() throws -> String {
        try self.derEncoded().base64Urlsafe
    }
}
// Convenience extensions for DER coding
internal extension Decodable {
    /// DER decodes `self` from `derEncoded`
    ///
    ///  - Parameter derEncoded: The DER encoded bytes
    ///  - Throws: `DERError` in case of decoding errors
    init(derEncoded: Data) throws {
        self = try Asn1Coder.default.decode(Self.self, from: derEncoded)
    }
    /// DER decodes `self` from `derEncoded`
    ///
    ///  - Parameter derUrlsafeEncoded: The Base64Urlsafe+DER encoded bytes
    ///  - Throws: `DERError` in case of decoding errors
    init(derUrlsafeEncoded: String) throws {
        guard let data = Data(base64Urlsafe: derUrlsafeEncoded) else {
            throw DERError.invalidData("Invalid Base64Urlsafe encoding")
        }
        try self.init(derEncoded: data)
    }
}


/// A UUID
public struct UUID: Hashable, Codable {
    /// The UUID bytes
    public let bytes: Data
    
    /// Creates a new cryptographically secure 24 byte random UUID
    public init() {
        var bytes = Data(count: 24)
        precondition(bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(nil, $0.count, $0.baseAddress!) })
            == errSecSuccess, "Failed to generate random bytes")
        self.bytes = bytes
    }
    /// Generates a UUID from a predefined/assigned value
    ///
    ///  - Parameter predefined: The predefined UUID
    ///
    ///  - Warning: The predefined UUID should be unique within it's environment and should not be longer than 24 bytes
    ///    or else it might cause undefined behaviour/weird bugs.
    public init<D: DataProtocol>(predefined: D) {
        self.bytes = Data(predefined)
    }
    /// Generates a UUID from a predefined/assigned value
    ///
    ///  - Parameter predefined: The predefined UUID
    ///
    ///  - Warning: The predefined UUID should be unique within it's environment and should not be longer than 24 bytes
    ///    or else it might cause undefined behaviour/weird bugs.
    public init<S: StringProtocol>(predefined: S) {
        self.init(predefined: predefined.data(using: .utf8)!)
    }
    
    // Override default encoding to use `bytes` as top-level object instead of encapsulating it in a sequence
    public func encode(to encoder: Encoder) throws {
        try bytes.encode(to: encoder)
    }
    // Override default encoding to use `bytes` as top-level object instead of encapsulating it in a sequence
    public init(from decoder: Decoder) throws {
        self.bytes = try Data(from: decoder)
    }
}


/// A connection ID
public struct ConnectionID: Hashable, Codable {
    /// The local client UUID
    public let local: UUID
    /// The remote client UUID
    public let remote: UUID
    
    /// Creates a new connection ID
    ///
    ///  - Parameters:
    ///     - local: The UUID of the local connection half
    ///     - remote: The UUID of the remote connection half
    public init(local: UUID, remote: UUID) {
        self.local = local
        self.remote = remote
    }
}


/// A state object
internal struct StateObject: Codable {
    /// The amount of messages received `remote->local`
    public var counterRX: UInt64
    /// The amount of messages sent `local->remote`
    public var counterTX: UInt64
    
    /// Creates a new connection ID
    ///
    ///  - Parameters:
    ///     - counterTX: The initial send counter value
    ///     - counterRX: The initial receive counter value
    public init(counterTX: UInt64 = 0, counterRX: UInt64 = 0) {
        self.counterRX = counterRX
        self.counterTX = counterTX
    }
}


/// A message header
internal struct MessageHeader: Codable {
    /// The message sender
    public let sender: UUID
    /// The message receiver
    public let receiver: UUID
    /// The message counter
    public let counter: UInt64
    
    /// Creates a new message header
    ///
    ///  - Parameters:
    ///     - sender: The message sender
    ///     - receiver: The message receiver
    ///     - counter: The message counter in the `sender->receiver` context
    public init(sender: UUID, receiver: UUID, counter: UInt64) {
        self.sender = sender
        self.receiver = receiver
        self.counter = counter
    }
}
