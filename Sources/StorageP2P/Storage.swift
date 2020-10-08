import Foundation


/// A 64 bit counter
public protocol Counter {
    /// The StorageP2P counter value
    var value: UInt64 { get set }
}
extension UInt64: Counter {
    public var value: UInt64 {
        get { self }
        set { self = newValue }
    }
}


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
    mutating func write<D: DataProtocol>(name: D, data: Data) throws
    /// Deletes an entry if it exists
    ///
    ///  - Parameter name: The name of the entry to delete
    ///  - Throws: If the entry exists but cannot be deleted (it is *not* an error if the entry does not exist)
    mutating func delete<D: DataProtocol>(name: D) throws
}
