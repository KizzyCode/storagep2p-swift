import Foundation
import Asn1Der


/// Scans a storage to discovery pending connections
public struct Discovery {
    /// The storage used to exchange messages
    public let storage: Storage
    
    /// Scans all entries for pending messages to a local half
    ///
    ///  - Parameter local: The UUID of the local endpoint to scan for
    public func scan(local: UUID) throws -> [ConnectionID] {
        try self.storage.list()
            .compactMap({ try? MessageHeader(derEncoded: $0) })
            .filter({ $0.receiver == local })
            .map({ ConnectionID(local: $0.receiver, remote: $0.sender) })
    }
}


/// A read-only connection viewer
public class Viewer {
    /// The connection ID
    public let id: ConnectionID
    /// The RX position within the connection
    internal(set) public var position: Counter
    /// The storage used to exchange messages
    internal let storage: Storage
    
    /// Creates a new connection viewer
    ///
    ///  - Parameters:
    ///     - id: The connection ID
    ///     - position: The RX position within the connection (i.e. the amount of messages received, required to resume
    ///                 a connection)
    ///     - storage: The storage used to exchange messages
    public init(id: ConnectionID, at position: Counter = UInt64(0), storage: Storage) {
        self.id = id
        self.position = position
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
        // Read the message if it exists
        let header = MessageHeader(sender: self.id.remote, receiver: self.id.local,
                                   counter: self.position.sp2pCounter + nth)
        guard try self.storage.list().contains(header.derEncoded()) else {
            return nil
        }
        return try self.storage.read(name: header.derEncoded())
    }
}


/// A connection reader
public class Receiver: Viewer {
    /// The storage used to exchange messages
    internal let mutableStorage: MutableStorage
    
    /// Creates a new connection receiver
    ///
    ///  - Parameters:
    ///     - id: The connection ID
    ///     - position: The position within the connection (i.e. the amount of messages received, required to resume a
    ///                 connection)
    ///     - storage: The storage used to exchange messages
    public init(id: ConnectionID, at position: Counter = UInt64(0), storage: MutableStorage) {
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
        // Write the message
        let header = MessageHeader(sender: self.id.remote, receiver: self.id.local,
                                   counter: self.position.sp2pCounter)
        let message = try self.storage.read(name: header.derEncoded())
        self.position.sp2pCounter += 1
        
        // Perform an opportunistic garbage collection
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
        let position = self.position.sp2pCounter
        try self.storage.list()
            .compactMap({ try? MessageHeader(derEncoded: $0) })
            .filter({ $0.sender == self.id.remote && $0.receiver == self.id.local })
            .filter({ $0.counter < position })
            .forEach({ try self.mutableStorage.delete(name: $0.derEncoded()) })
    }
}


/// A sender
public class Sender {
    /// The connection ID
    public let id: ConnectionID
    /// The TX position within the connection
    internal(set) public var position: Counter
    /// The storage used to exchange messages
    internal let storage: MutableStorage
    
    /// Creates a new connection receiver
    ///
    ///  - Parameters:
    ///     - id: The connection ID
    ///     - position: The position within the connection (i.e. the amount of messages sent, required to resume a
    ///                 connection)
    ///     - storage: The storage used to exchange messages
    public init(id: ConnectionID, at position: Counter = UInt64(0), storage: MutableStorage) {
        self.id = id
        self.position = position
        self.storage = storage
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
        // Write the message
        let header = MessageHeader(sender: self.id.local, receiver: self.id.remote, counter: self.position.sp2pCounter)
        try self.storage.write(name: header.derEncoded(), data: message)
        self.position.sp2pCounter += 1
    }
}
