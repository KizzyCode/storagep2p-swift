import Foundation


/// A read-only storage
public protocol Storage {
    /// Lists all entries in the storage
    ///
    ///  - Returns: The names of the stored entries
    ///  - Throws: An exception if the listing fails
    func list() throws -> [Data]
    /// Reads an entry
    ///
    ///  - Parameter name: The name of the entry to read
    ///  - Returns: The contents of the entry
    ///  - Throws: An exception if the entry does not exist or cannot be read
    func read<D: DataProtocol>(name: D) throws -> Data
}


/// A mutable storage
public protocol MutableStorage: Storage {
    /// Atomically creates/replaces an entry
    ///
    ///  - Parameters:
    ///     - name: The name of the entry to create. The name is not longer than 100 bytes and contains only characters
    ///       from the Base64Urlsafe character set (without `=`).
    ///     - data: The entry data
    ///  - Throws: If the entry cannot be written
    mutating func write<N: DataProtocol, D: DataProtocol>(name: N, data: D) throws
    /// Deletes an entry if it exists
    ///
    ///  - Parameter name: The name of the entry to delete
    ///  - Throws: If the entry exists but cannot be deleted (it is *not* an error if the entry does not exist)
    mutating func delete<D: DataProtocol>(name: D) throws
}


/// A persistent storage provider for connection states
public protocol ConnectionStates {
    /// Lists all connections for which a state is stored
    ///
    ///  - Returns: The IDs of all connection for which a state is stored
    func list() throws -> Set<ConnectionID>
    
    /// Loads a connection state object if any
    ///
    ///  - Parameter connection: The ID of the connection
    ///  - Returns: The stored connection state object
    func load(connection: ConnectionID) throws -> ConnectionStateObject
}


/// A mutable persistent storage provider for connection states
public protocol MutableConnectionStates: ConnectionStates {
    /// Stores a new connection state object
    ///
    ///  - Parameters:
    ///     - connection: The ID of the connection
    ///     - state: The new state object or `nil` to delete the state object
    mutating func store(connection: ConnectionID, state: ConnectionStateObject?) throws
}
