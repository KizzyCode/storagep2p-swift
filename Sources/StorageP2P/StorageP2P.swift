import Foundation
import Asn1Der


/// Scans a storage to discovery pending connections
public struct Discovery {
    /// The storage used to exchange messages
    public let storage: Storage
    
    /// Creates a new instance that scans a specific storage
    ///
    ///  - Parameter storage: The storage used to exchange messages
    public init(storage: Storage) {
        self.storage = storage
    }
    
    /// Scans all entries for pending messages sent to a specific endpoint
    ///
    ///  - Parameter local: The ID of the local endpoint
    ///  - Returns: All connections that have pending messages `* -> local`
    public func scan(local: UniqueID) throws -> [ConnectionID] {
        try self.storage.list()
            .compactMap({ try? DERDecoder().decode(MessageHeader.self, from: $0) })
            .filter({ $0.receiver == local })
            .map({ ConnectionID(local: $0.receiver, remote: $0.sender) })
    }
}


/// A read-only connection viewer
public class Viewer {
    /// The connection ID
    public let id: ConnectionID
    /// The RX position within the connection
    internal(set) public var position: BoxedValueProvider<UInt64>
    /// The storage used to exchange messages
    internal let storage: Storage
    
    /// Creates a new connection viewer
    ///
    ///  - Parameters:
    ///     - id: The connection ID
    ///     - position: The RX position within the connection (i.e. the amount of messages received, required to resume
    ///                 a connection)
    ///     - storage: The storage used to exchange messages
    public init<T: ValueProvider>(id: ConnectionID, at position: T, storage: Storage) where T.Value == UInt64 {
        self.id = id
        self.position = BoxedValueProvider(position)
        self.storage = storage
    }
    
    /// Takes a peek at the `nth` pending message
    ///
    ///  - Idempotency: This function is read-only and does not modify any state.
    ///
    ///  - Parameter nth: The index of the message to peek at starting at the current position (i.e. the `nth` pending
    ///                   message)
    ///  - Returns: The `nth` pending message if any
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func peek(nth: UInt64 = 0) throws -> Data? {
        // Create the header
        let header = MessageHeader(sender: self.id.remote, receiver: self.id.local, counter: self.position.value + nth),
            headerBytes = try DEREncoder().encode(header)
        
        // Read the message
        guard try self.storage.list().contains(headerBytes) else {
            return nil
        }
        return try self.storage.read(name: headerBytes)
    }
}


/// A connection reader
public class Receiver: Viewer {
    /// The storage used to exchange messages
    internal var mutableStorage: MutableStorage
    
    /// Creates a new connection receiver
    ///
    ///  - Parameters:
    ///     - id: The connection ID
    ///     - position: The position within the connection (i.e. the amount of messages received, required to resume a
    ///                 connection)
    ///     - storage: The storage used to exchange messages
    public init<T: ValueProvider>(id: ConnectionID, at position: T, storage: MutableStorage) where T.Value == UInt64 {
        self.mutableStorage = storage
        super.init(id: id, at: position, storage: storage)
    }
    
    /// Receives the next message if any
    ///
    ///  - Info: This function performs an opportunistic garbage after receiving; however errors are silently ignored.
    ///    If you want to ensure that a garbage collection is performed, call `gc` manually.
    ///
    ///  - Idempotency: This function is __not__ idempotent. However __on error__ this function will not update the
    ///    connection position so that it can be simply called again until it succeeds (i.e. this function provides some
    ///    sort of "idempotency on error").
    ///
    ///  - Returns: The received message if any
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func receive() throws -> Data? {
        // Create the header
        let header = MessageHeader(sender: self.id.remote, receiver: self.id.local, counter: self.position.value),
            headerBytes = try DEREncoder().encode(header)
        
        // Receive the message
        let message = try self.storage.read(name: headerBytes)
        self.position.value += 1
        
        // Perform an opportunistic garbage collection and return
        try? self.gc()
        return message
    }
    
    /// Removes all already received messages from the storage
    ///
    ///  - Idempotency: This function is idempotent.
    ///
    ///  - Parameter conn: The connection to clean up
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func gc() throws {
        // Capture state and delete all messages `remote -> local` where `message.counter < state.counterRX`
        let position = self.position.value
        for headerBytes in try self.storage.list() {
            // Decode the header
            if let header = try? DERDecoder().decode(MessageHeader.self, from: headerBytes) {
                // Delete the message if it
                //  - belongs to our connection
                //  - is an incoming message
                //  - has been received (i.e. it's counter is lower then the current position)
                if header.sender == self.id.remote && header.receiver == self.id.local && header.counter < position {
                    try self.mutableStorage.delete(name: headerBytes)
                }
            }
        }
    }
}


/// A sender
public class Sender {
    /// The connection ID
    public let id: ConnectionID
    /// The TX position within the connection
    internal(set) public var position: BoxedValueProvider<UInt64>
    /// The storage used to exchange messages
    internal var mutableStorage: MutableStorage
    
    /// Creates a new connection receiver
    ///
    ///  - Parameters:
    ///     - id: The connection ID
    ///     - position: The position within the connection (i.e. the amount of messages sent, required to resume a
    ///                 connection)
    ///     - storage: The storage used to exchange messages
    public init<T: ValueProvider>(id: ConnectionID, at position: T, storage: MutableStorage) where T.Value == UInt64 {
        self.id = id
        self.position = BoxedValueProvider(position)
        self.mutableStorage = storage
    }
    
    /// Sends a message
    ///
    ///  - Idempotency: This function is __not__ idempotent. However __on error__ this function will not update the
    ///    connection state so that it can be simply called again until it succeeds (i.e. this function provides some
    ///    sort of "idempotency on error").
    ///
    ///  - Parameter message: The message to send
    ///  - Throws: If a local or remote I/O-error occurred
    public func send(message: Data) throws {
        // Create the header
        let header = MessageHeader(sender: self.id.local, receiver: self.id.remote, counter: self.position.value),
            headerBytes = try DEREncoder().encode(header)
        
        // Write the message
        try self.mutableStorage.write(name: headerBytes, data: message)
        self.position.value += 1
    }
}
