import Foundation
import PersistentState
import Asn1Der


/// A StorageP2P socket
public class Socket {
    /// The storage key for the state object
    private static let stateKey = "de.KizzyCode.StorageP2P.Socket.State"
    
    /// The persistent state
    private let state: PersistentDict<ConnectionID, StateObject>
    /// The storage to use to exchange the messages
    private let storage: Storage
    
    /// Creates a new socket
    ///
    ///  - Parameters:
    ///     - persistent: A (local) reliable persistent storage to store the connection counters (see
    ///       `PersistentState.Storage` for more info)
    ///     - storage: The message storage that is used to exchange the message (e.g. a cloud-backed storage)
    public init(persistent: PersistentState.Storage, storage: Storage) {
        self.state = PersistentDict(storage: persistent, key: Self.stateKey)
        self.storage = storage
    }
    
    /// Lists all existing connections `local <-> *` that have at least one message sent/received and returns the
    /// connection IDs
    ///
    ///  - Parameter local: The UUID of the local connection endpoint
    ///  - Returns: All connections between `local <-> *`
    ///  - Throws: If an entry is invalid or if a local or remote I/O-error occurred
    public func list(local: UUID) throws -> Set<ConnectionID> {
        // List the locally known connections and add all new incoming connections
        var ids = Set(state.dict.keys)
        try self.storage.list()
            .compactMap({ try? MessageHeader(derUrlsafeEncoded: $0) })
            .filter({ $0.receiver == local })
        	.map({ ConnectionID(local: $0.receiver, remote: $0.sender) })
            .forEach({ ids.insert($0) })
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
        guard try self.storage.list().contains(header.derEncodedUrlsafe()) else {
            return nil
        }
        return try self.storage.read(name: header.derEncodedUrlsafe())
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
        try self.state(key: conn, default: StateObject(), {
            let header = MessageHeader(sender: conn.local, receiver: conn.remote, counter: $0.counterTX)
            try self.storage.write(name: header.derEncodedUrlsafe(), data: message)
            $0.counterTX += 1
        })
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
        return try self.storage.list().contains(header.derEncodedUrlsafe())
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
        try self.state(key: conn, default: StateObject(), {
            let header = MessageHeader(sender: conn.remote, receiver: conn.local, counter: $0.counterRX)
            message = try self.storage.read(name: header.derEncodedUrlsafe())
            $0.counterRX += 1
        })
        
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
            .compactMap({ try? MessageHeader(derUrlsafeEncoded: $0) })
            .filter({ $0.sender == conn.remote && $0.receiver == conn.local })
            .filter({ $0.counter < state.counterRX })
            .forEach({ try self.storage.delete(name: $0.derEncodedUrlsafe()) })
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
            .compactMap({ try? MessageHeader(derUrlsafeEncoded: $0) })
        
        // Filter for `local -> remote` and `remote -> local`
        var toDelete: [MessageHeader] = []
        toDelete += headers.filter({ $0.sender == conn.local && $0.receiver == conn.remote })
        toDelete += headers.filter({ $0.sender == conn.remote && $0.receiver == conn.local })
        
        // Delete all messages and the associated state
        try headers.forEach({ try self.storage.delete(name: $0.derEncodedUrlsafe()) })
        self.state[conn] = nil
    }
}
