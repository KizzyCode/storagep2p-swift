import Foundation
import Asn1Der


/// An endpoint address
public struct Address: Hashable, Codable {
    /// The address bytes
    public let bytes: Data
    
    /// Creates a new cryptographically secure 24 byte random address
    public init() {
        var bytes = Data(count: 24)
        precondition(bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(nil, $0.count, $0.baseAddress!) })
            == errSecSuccess, "Failed to generate random bytes")
        self.bytes = bytes
    }
    /// Generates an address from a predefined/assigned value
    ///
    ///  - Parameter predefined: The predefined address
    ///
    ///  - Warning: The predefined address should be unique within it's environment and should not be longer than 24
    ///             bytes or else it might cause undefined behaviour/weird bugs.
    public init<D: DataProtocol>(predefined: D) {
        self.bytes = Data(predefined)
    }
    /// Generates an address from a predefined/assigned value
    ///
    ///  - Parameter predefined: The predefined address
    ///
    ///  - Warning: The predefined address should be unique within it's environment and should not be longer than 24
    ///             bytes or else it might cause undefined behaviour/weird bugs.
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
    /// The local client address
    public let local: Address
    /// The remote client address
    public let remote: Address
    
    /// Creates a new connection ID
    ///
    ///  - Parameters:
    ///     - local: The address of the local connection endpoint
    ///     - remote: The address of the remote connection endpoint
    public init(local: Address, remote: Address) {
        self.local = local
        self.remote = remote
    }
}


/// A state object
public struct StateObject: Codable {
    /// The amount of messages received `remote->local`
    internal(set) public var counterRX: UInt64
    /// The amount of messages sent `local->remote`
    internal(set) public var counterTX: UInt64
    
    /// Creates a new connection ID
    ///
    ///  - Parameters:
    ///     - counterTX: The initial send counter value
    ///     - counterRX: The initial receive counter value
    internal init(counterTX: UInt64 = 0, counterRX: UInt64 = 0) {
        self.counterRX = counterRX
        self.counterTX = counterTX
    }
}


/// A message header
internal struct MessageHeader: Codable {
    /// The message sender
    public let sender: Address
    /// The message receiver
    public let receiver: Address
    /// The message counter
    public let counter: UInt64
    
    /// Creates a new message header
    ///
    ///  - Parameters:
    ///     - sender: The message sender
    ///     - receiver: The message receiver
    ///     - counter: The message counter in the `sender->receiver` context
    public init(sender: Address, receiver: Address, counter: UInt64) {
        self.sender = sender
        self.receiver = receiver
        self.counter = counter
    }
}
