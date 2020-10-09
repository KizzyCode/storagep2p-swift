import Foundation


/// A value provider
open class ValueProvider<T> {
    /// A computed property that wraps the `load` and `store` calls
    open var value: T {
        get { try! self.load() }
        set { try! self.store(newValue) }
    }
    
    /// An initializer
    ///
    ///  - Warning: Don't call this initializer directly. This class must always be initialized through it's subclasses.
    public init() {}
    
    /// Loads the value
    ///
    ///  - Returns: The loaded value
    open func load() throws -> T {
        fatalError("This function must be overridden by the subclass")
    }
    /// Stores the value
    ///
    ///  - Parameter newValue: The new value to store
    open func store(_ newValue: T) throws {
        fatalError("This function must be overridden by the subclass")
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
    mutating func write<D0: DataProtocol, D1: DataProtocol>(name: D0, data: D1) throws
    /// Deletes an entry if it exists
    ///
    ///  - Parameter name: The name of the entry to delete
    ///  - Throws: If the entry exists but cannot be deleted (it is *not* an error if the entry does not exist)
    mutating func delete<D: DataProtocol>(name: D) throws
}
