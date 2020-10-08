import Foundation
import Asn1Der


/// A persistent state object
public protocol State {
    /// The state object
    var stateDict: [ConnectionID: StateObject] { get set }
}
internal extension State {
    /// The state dictionary keys
    var keys: Dictionary<ConnectionID, StateObject>.Keys { self.stateDict.keys }
    
    /// Gets the current value or inserts a new value and returns it
    ///
    ///  - Parameters:
    ///     - key: The key
    ///     - value: The value
    ///  - Returns: The value
    mutating func getOrInsert(key: ConnectionID, default: StateObject) -> StateObject {
        if self.stateDict[key] == nil {
            self.stateDict[key] = `default`
        }
        return self.stateDict[key]!
    }
    
    /// Gets or sets a value
    subscript(_ key: ConnectionID) -> StateObject? {
        get { self.stateDict[key] }
        set { self.stateDict[key] = newValue }
    }
}


/// A StorageP2P socket
public class Socket {
    /// The persistent state
    private var state: State
    /// The storage to use to exchange the messages
    private let storage: Storage
    
    /// Creates a new socket
    ///
    ///  - Parameters:
    ///     - state: A reliable persistent state object to store the connection counters (see
    ///       `PersistentState.Storage` for more info)
    ///     - storage: The message storage that is used to exchange the message (e.g. a cloud-backed storage)
    public init(state: State, storage: Storage) {
        self.state = state
        self.storage = storage
    }
    
    /// Discovers all existing connections `local <-> *` that have at least one message sent/received
    ///
    ///  - Idempotency: This function is read-only and does not modify any state.
    ///
    ///  - Parameter local: The UUID of the local connection endpoint
    ///  - Returns: All connections between `local <-> *`
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func discover(local: UUID) throws -> Set<ConnectionID> {
        // List the locally known connections and add all new incoming connections
        var ids = Set(self.state.keys)
        try self.storage.list()
            .compactMap({ try? MessageHeader(derEncoded: $0) })
            .filter({ $0.receiver == local })
            .map({ ConnectionID(local: $0.receiver, remote: $0.sender) })
            .forEach({ ids.insert($0) })
        return ids
    }
    /// Discovers all UUIDs that participate in at least one connection
    ///
    ///  - Idempotency: This function is read-only and does not modify any state.
    ///
    ///  - Returns: All client UUIDs that participate in at least one connection
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func discover() throws -> Set<UUID> {
        var ids = Set<UUID>()
        self.state.keys.forEach({
            ids.insert($0.local)
            ids.insert($0.remote)
        })
        try self.storage.list()
            .compactMap({ try? MessageHeader(derEncoded: $0) })
            .forEach({
            	ids.insert($0.sender)
            	ids.insert($0.receiver)
        	})
        return ids
    }
    
    /// Takes a peek at the `nth` pending message if any on the given connection
    ///
    ///  - Idempotency: This function is read-only and does not modify any state.
    ///
    ///  - Parameters:
    ///     - conn: The connection to peek at
    ///     - nth: The index of the pending message to peek at (i.e. the `nth` pending message)
    ///  - Returns: The `nth` pending message if any
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func peek(conn: ConnectionID, nth: Int = 0) throws -> Data? {
        // Create the header of the nth expected message
        let state = self.state.getOrInsert(key: conn, default: StateObject())
        let header = MessageHeader(sender: conn.remote, receiver: conn.local, counter: state.counterRX + UInt64(nth))
        
        // Receive the message if it exists
        guard try self.storage.list().contains(header.derEncoded()) else {
            return nil
        }
        return try self.storage.read(name: header.derEncoded())
    }
    
    /// Sends a message `local -> remote`
    ///
    ///  - Idempotency: This function is __not__ idempotent. However __on error__ this function will not update the
    ///    connection state so that it can be simply called again until it succeeds (i.e. this function provides some
    ///    sort of "idempotency on error").
    ///
    ///  - Parameters:
    ///     - conn: The connection to send the message over
    ///     - message: The message to send
    ///  - Throws: If a local or remote I/O-error occurred
    public func send(conn: ConnectionID, message: Data) throws {
        // Get the state
        var state = self.state.getOrInsert(key: conn, default: StateObject())
        defer { self.state[conn] = state }
        
        // Write the message
        let header = MessageHeader(sender: conn.local, receiver: conn.remote, counter: state.counterTX)
        try self.storage.write(name: header.derEncoded(), data: message)
        state.counterTX += 1
    }
    
    /// Checks whether there are incoming messages available on the given connection
    ///
    ///  - Idempotency: This is read-only and does not modify any state.
    ///
    ///  - Parameter conn: The connection to receive the message from
    ///  - Returns: Whether there is a message pending or not
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func canReceive(conn: ConnectionID) throws -> Bool {
        // Create the header of the next expected message and check if it exists
        let state = self.state.getOrInsert(key: conn, default: StateObject())
        let header = MessageHeader(sender: conn.remote, receiver: conn.local, counter: state.counterRX)
        return try self.storage.list().contains(header.derEncoded())
    }
    /// Receives the next message
    ///
    ///  - Info: This function performs an opportunistic garbage after receiving; however errors are silently ignored.
    ///    If you want to ensure that a garbage collection is performed, call `gc` manually.
    ///
    ///  - Idempotency: This function is __not__ idempotent. However __on error__ this function will not update the
    ///    connection state so that it can be simply called again until it succeeds (i.e. this function provides some
    ///    sort of "idempotency on error").
    ///
    ///  - Parameter conn: The connection to receive the message from
    ///  - Returns: The received message
    ///  - Throws: If there is not pending message, an entry is invalid or if a local or remote I/O-error occurred
    public func receive(conn: ConnectionID) throws -> Data {
        // Read next message
        var message: Data!
        
        // Get the state
        var state = self.state.getOrInsert(key: conn, default: StateObject())
        defer { self.state[conn] = state }
        
        // Write the message
        let header = MessageHeader(sender: conn.remote, receiver: conn.local, counter: state.counterRX)
        message = try self.storage.read(name: header.derEncoded())
        state.counterRX += 1
        
        // Perform an opportunistic garbage collection
        try? self.gc(conn: conn)
        return message
    }
    
    /// Performs a garbage collection on the given connection which removes all already received messages
    ///
    ///  - Idempotency: This function is idempotent.
    ///
    ///  - Parameter conn: The connection to clean up
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func gc(conn: ConnectionID) throws {
        // Capture state and delete all messages `remote -> local` where `message.counter < state.counterRX`
        let state = self.state.getOrInsert(key: conn, default: StateObject())
        try self.storage.list()
            .compactMap({ try? MessageHeader(derEncoded: $0) })
            .filter({ $0.sender == conn.remote && $0.receiver == conn.local })
            .filter({ $0.counter < state.counterRX })
            .forEach({ try self.storage.delete(name: $0.derEncoded()) })
    }
    
    /// Destroys this connection and deletes all associated messages
    ///
    ///  - Important: This function also deletes the connection state which makes it impossible to reopen a connection
    ///    `local <-> remote` unless the remote side also resets the state. This function is useful if e.g. the remote
    ///    side does not exist anymore or the counters are out of sync.
    ///
    ///  - Idempotency: This function is __not__ idempotent. However __on error__ this function will not delete the
    ///    connection state so that it can be simply called again until it succeeds (i.e. this function provides some
    ///    sort of "idempotency on error").
    ///
    ///  - Parameter conn: The connectino to destroy
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func destroy(conn: ConnectionID) throws {
        // List all messages
        let headers = try self.storage.list()
            .compactMap({ try? MessageHeader(derEncoded: $0) })
        
        // Filter for `local -> remote` and `remote -> local`
        var toDelete: [MessageHeader] = []
        toDelete += headers.filter({ $0.sender == conn.local && $0.receiver == conn.remote })
        toDelete += headers.filter({ $0.sender == conn.remote && $0.receiver == conn.local })
        
        // Delete all messages and the associated state
        try headers.forEach({ try self.storage.delete(name: $0.derEncoded()) })
        self.state[conn] = nil
    }
}
