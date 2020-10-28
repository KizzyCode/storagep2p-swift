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
    internal let states: ConnectionStates
    /// The storage used to exchange messages
    internal let storage: Storage
    
    /// The counter values
    internal var state: ConnectionStateObject {
        try! self.states.load(connection: self.id)
    }
    
    /// Creates a new connection viewer
    ///
    ///  - Parameters:
    ///     - id: The connection ID
    ///     - states: The persistent connection state object
    ///     - storage: The storage used to exchange messages
    public init(id: ConnectionID, states: ConnectionStates, storage: Storage) {
        self.id = id
        self.states = states
        self.storage = storage
    }
    
    /// Gets the amount of pending messages
    ///
    ///  - Returns: The amount of pending messages
    public func pending() throws -> UInt64 {
        // List and index all message headers
        let headers = try Set(self.storage.list()),
            counter = self.state.rx
        
        // Scan for pending messages
        for nth in counter ... UInt64.max {
            // Create the header
            let header = MessageHeader(sender: self.id.remote, receiver: self.id.local, counter: nth),
                headerBytes = try DEREncoder().encode(header)
            
            // Check whether the message exists
            guard headers.contains(headerBytes) else {
                return nth
            }
        }
        fatalError("Unreachable: There cannot be more than `UInt64.max` pending messages")
    }
    /// Takes a peek at the `nth` pending message if it exists
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
    /// The mutable persistent connection states
    internal var mutableStates: MutableConnectionStates
    /// The storage used to exchange messages
    internal var mutableStorage: MutableStorage
    
    /// The state for the current connection
    override internal(set) public var state: ConnectionStateObject {
        get { try! self.mutableStates.load(connection: self.id) }
        set { try! self.mutableStates.store(connection: self.id, state: newValue) }
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
    ///     - states: The persistent connection state object
    ///     - storage: The storage used to exchange messages
    public init(id: ConnectionID, states: MutableConnectionStates, storage: MutableStorage) {
        self.mutableStates = states
        self.mutableStorage = storage
        super.init(id: id, states: states, storage: storage)
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
    
    /// Receives the next message, passes it to `block` and updates the state *if* `block` *succeeds*
    ///
    ///  - Idempotency: This function is __not__ idempotent. However __on error__ (e.g. an I/O-error or if `block`
    ///    throws) this function will not update the connection state so that it can be simply called again until it
    ///    succeeds (i.e. this function provides some sort of "idempotency on error").
    ///
    ///  - Warning: Due to performance reasons, this function does not perform any kind of garbage collection. To remove
    ///    the received messages from the storage, call the `gc()`-function manually.
    ///
    ///  - Parameter block: A block that processes the incoming message
    ///  - Returns: The result of `block`
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func receive<R>(_ block: (Data) throws -> R) throws -> R {
        // Read the message
        let headerBytes = try DEREncoder().encode(self.nextHeader.rx),
            message = try self.storage.read(name: headerBytes)
        
        // Call block and update the state on success
        let result = try block(message)
        self.state.rx += 1
        return result
    }
    /// Receives the next message
    ///
    ///  - Idempotency: This function is __not__ idempotent. However __on error__ this function will not update the
    ///    connection state so that it can be simply called again until it succeeds (i.e. this function provides some
    ///    sort of "idempotency on error").
    ///
    ///  - Warning: Due to performance reasons, this function does not perform any kind of garbage collection. To remove
    ///    the received messages from the storage, call the `gc()`-function manually.
    ///
    ///  - Returns: The received message
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func receive() throws -> Data {
        try self.receive({ $0 })
    }
    
    /// Removes all already received messages from the storage
    ///
    ///  - Idempotency: This function is idempotent.
    ///
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
