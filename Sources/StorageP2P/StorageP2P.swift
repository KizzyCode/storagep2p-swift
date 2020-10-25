import Foundation
import Asn1Der
import ValueProvider


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
    public func scan(local: UniqueID) throws -> Set<ConnectionID> {
        try self.storage.list()
            .compactMap({ try? DERDecoder().decode(MessageHeader.self, from: $0) })
            .filter({ $0.receiver == local })
            .reduce(into: Set(), { $0.insert(ConnectionID(local: $1.receiver, remote: $1.sender)) })
    }
}


/// A read-only connection viewer
public class ConnectionViewer {
    /// The connection ID
    public let id: ConnectionID
    /// The persistent connection states
    internal var persistent: AnyMappedDictionary<ConnectionID, ConnectionState>
    /// The storage used to exchange messages
    internal let storage: Storage
    
    /// The state for the current connection
    public var state: ConnectionState {
        self.persistent[self.id] ?? ConnectionState()
    }
    
    /// Creates a new connection viewer
    ///
    ///  - Parameters:
    ///     - id: The connection ID
    ///     - state: The persistent connection state object
    ///     - storage: The storage used to exchange messages
    public init<S: MappedDictionary>(id: ConnectionID, state: S, storage: Storage)
        where S.Key == ConnectionID, S.Value == ConnectionState
    {
        self.id = id
        self.persistent = AnyMappedDictionary(state)
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
        let header = MessageHeader(sender: self.id.remote, receiver: self.id.local, counter: self.state.rx + nth),
            headerBytes = try DEREncoder().encode(header)
        
        // Read the message
        guard try self.storage.list().contains(headerBytes) else {
            return nil
        }
        return try self.storage.read(name: headerBytes)
    }
}


/// A connection
public class Connection: ConnectionViewer {
    /// The storage used to exchange messages
    internal var mutableStorage: MutableStorage
    
    /// The state for the current connection
    override internal(set) public var state: ConnectionState {
        get { self.persistent[self.id] ?? ConnectionState() }
        set { self.persistent[self.id] = newValue }
    }
    
    /// Gets the headers of the next incoming and outgoing messages
    ///
    ///  - Returns: The header of the next incoming message (`rx`) and the header of the next outgoing message (`tx`)
    ///
    ///  - Discussion: Each message has a header which is unique within a `StorageP2P` environment. This is not only
    ///    required for message delivery but can also be used to perform some message specific operations, e.g. deriving
    ///    per-message subkeys for encryption.
    public var nextHeader: (rx: MessageHeader, tx: MessageHeader) {
        return (
            rx: MessageHeader(sender: self.id.remote, receiver: self.id.local, counter: self.state.rx),
            tx: MessageHeader(sender: self.id.local, receiver: self.id.remote, counter: self.state.tx))
    }
    
    /// Creates a new connection receiver
    ///
    ///  - Parameters:
    ///     - id: The connection ID
    ///     - state: The persistent connection state object
    ///     - storage: The storage used to exchange messages
    public init<S: MappedDictionary>(id: ConnectionID, state: S, storage: MutableStorage)
        where S.Key == ConnectionID, S.Value == ConnectionState
    {
        self.mutableStorage = storage
        super.init(id: id, state: state, storage: storage)
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
        let headerBytes = try DEREncoder().encode(self.nextHeader.tx)
        try self.mutableStorage.write(name: headerBytes, data: message)
        self.state.tx += 1
    }
    
    /// Receives the next message if any
    ///
    ///  - Info: This function performs an opportunistic garbage after receiving; however errors are silently ignored.
    ///    If you want to ensure that a garbage collection is performed, call `gc` manually.
    ///
    ///  - Idempotency: This function is __not__ idempotent. However __on error__ this function will not update the
    ///    connection state so that it can be simply called again until it succeeds (i.e. this function provides some
    ///    sort of "idempotency on error").
    ///
    ///  - Returns: The received message if any
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func receive() throws -> Data? {
        // Receive the message
        let headerBytes = try DEREncoder().encode(self.nextHeader.rx),
            message = try self.storage.read(name: headerBytes)
        self.state.rx += 1
        
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
        let position = self.state.rx
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
