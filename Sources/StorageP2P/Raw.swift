import Foundation
import Asn1Der
import ValueProvider


/// A persistent connection state object
public typealias ConnectionState = AnyMappedDictionary<ConnectionID, StateObject>


/// A unique ID
public struct UniqueID: Hashable, Codable {
    /// The ID bytes
    public let bytes: Data
    
    /// Creates a new cryptographically secure 24 byte random ID
    public init() {
        var bytes = Data(count: 24)
        precondition(bytes.withUnsafeMutableBytes({ SecRandomCopyBytes(nil, $0.count, $0.baseAddress!) })
            == errSecSuccess, "Failed to generate random bytes")
        self.bytes = bytes
    }
    /// Generates an ID from a predefined/assigned value
    ///
    ///  - Parameter predefined: The predefined ID
    ///
    ///  - Warning: The predefined ID should be unique within it's environment and should not be longer than 24 bytes or
    ///             else it might cause undefined behaviour/weird bugs.
    public init<D: DataProtocol>(predefined: D) {
        self.bytes = Data(predefined)
    }
    /// Generates an ID from a predefined/assigned value
    ///
    ///  - Parameter predefined: The predefined ID
    ///
    ///  - Warning: The predefined ID should be unique within it's environment and should not be longer than 24 bytes or
    ///             else it might cause undefined behaviour/weird bugs.
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
    /// The local client ID
    public let local: UniqueID
    /// The remote client ID
    public let remote: UniqueID
    
    /// Creates a new connection ID
    ///
    ///  - Parameters:
    ///     - local: The ID of the local connection endpoint
    ///     - remote: The ID of the remote connection endpoint
    public init(local: UniqueID, remote: UniqueID) {
        self.local = local
        self.remote = remote
    }
}


/// A state object
public struct StateObject: Codable {
    /// The amount of messages received `remote->local`
    internal(set) public var rx: UInt64
    /// The amount of messages sent `local->remote`
    internal(set) public var tx: UInt64
    
    /// Creates a new connection ID
    ///
    ///  - Parameters:
    ///     - rx: The initial receive counter value
    ///     - tx: The initial send counter value
    public init(rx: UInt64 = 0, tx: UInt64 = 0) {
        self.rx = rx
        self.tx = tx
    }
}


/// A message header
internal struct MessageHeader: Codable {
    /// The message sender
    public let sender: UniqueID
    /// The message receiver
    public let receiver: UniqueID
    /// The message counter
    public let counter: UInt64
    
    /// Creates a new message header
    ///
    ///  - Parameters:
    ///     - sender: The message ID
    ///     - receiver: The message ID
    ///     - counter: The message counter in the `sender->receiver` context
    public init(sender: UniqueID, receiver: UniqueID, counter: UInt64) {
        self.sender = sender
        self.receiver = receiver
        self.counter = counter
    }
}
