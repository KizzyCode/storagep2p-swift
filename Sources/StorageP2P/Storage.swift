import Foundation


/// The storage to exchange the messages
public protocol Storage {
    /// Lists all entries in the storage
    ///
    ///  - Returns: The names of the stored entries
    ///  - Throws: An exception if the listing fails
    func list() throws -> [String]
    /// Reads an entry
    ///
    ///  - Parameter name: The name of the entry to read
    ///  - Returns: The contents of the entry
    ///  - Throws: An exception if the entry does not exist or cannot be read
    func read<S: StringProtocol>(name: S) throws -> Data
    /// Atomically creates/replaces an entry
    ///
    ///  - Parameters:
    ///     - name: The name of the entry to create. The name is not longer than 100 bytes and contains only characters
    ///       from the Base64Urlsafe character set (without `=`).
    ///     - data: The entry data
    ///  - Throws: If the entry cannot be written
    func write<S: StringProtocol>(name: S, data: Data) throws
    /// Deletes an entry if it exists
    ///
    ///  - Parameter name: The name of the entry to delete
    ///  - Throws: If the entry exists but cannot be deleted (it is *not* an error if the entry does not exist)
    func delete<S: StringProtocol>(name: S) throws
}


/// A read-only storage wrapper
public class ReadOnlyStorage: Storage {
    /// The associated error
    public enum Error: Swift.Error {
        /// The access was denied
        case accessDenied(String, String = #file, Int = #line)
    }
    
    /// The wrapped storage instance
    private let storage: Storage
    
    /// Creates a new read-only storage wrapper
    ///
    ///  - Parameter storage: The underlying storage
    public init(wrapping storage: Storage) {
        self.storage = storage
    }
    
    public func list() throws -> [String] {
        try self.storage.list()
    }
    public func read<S: StringProtocol>(name: S) throws -> Data {
        try self.storage.read(name: name)
    }
    public func write<S: StringProtocol>(name: S, data: Data) throws {
        throw Error.accessDenied("Cannot write because the storage is read-only")
    }
    public func delete<S: StringProtocol>(name: S) throws {
        throw Error.accessDenied("Cannot delete because the storage is read-only")
    }
}
