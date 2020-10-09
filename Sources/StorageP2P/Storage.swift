import Foundation


/// A value provider
public protocol ValueProvider {
    /// The value type
    associatedtype Value
    
    /// Loads the value
    ///
    ///  - Returns: The loaded value
    func load() throws -> Value
    /// Stores the value
    ///
    ///  - Parameter newValue: The new value to store
    mutating func store(_ newValue: Value) throws
}
public extension ValueProvider {
    /// A computed property that wraps the `load` and `store` calls
    var value: Value {
        get { try! self.load() }
        set { try! self.store(newValue) }
    }
}
extension UInt64: ValueProvider {
    public typealias Value = UInt64
    
    public func load() throws -> UInt64 {
        self
    }
    public mutating func store(_ newValue: UInt64) throws {
        self = newValue
    }
}


/// A boxed value provider to perform type erasure
public class BoxedValueProvider<T> {
    /// The getter
    private let getter: () throws -> T
    /// The setter
    private let setter: (T) throws -> Void

    /// Boxes a value provider
    ///
    ///  - Parameter provider: The value provider to box
    public init<P: ValueProvider>(_ provider: P) where P.Value == T {
        var provider = provider
        self.getter = { try provider.load() }
        self.setter = { try provider.store($0) }
    }
}
extension BoxedValueProvider: ValueProvider {
    public typealias Value = T
    
    public func load() throws -> T {
        try self.getter()
    }
    public func store(_ newValue: T) throws {
        try self.setter(newValue)
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
