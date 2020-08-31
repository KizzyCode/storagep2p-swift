import Foundation
import StorageP2P
import PersistentState


/// An filesystem related error
public enum StorageError: Error {
    /// A synthetic error for testing
    case syntheticError(StaticString = "A synthetic error for testing", StaticString = #file, Int = #line)
    /// The requested entry does not exists
    case noSuchEntry(StaticString = "No such entry", StaticString = #file, Int = #line)
}


/// A `PersistentState.Storage` implementation
public class PersistentStorageImpl {
    /// The state entries
    private var entries: [String: Data] = [:]
    
    /// Creates a new `StateImpl` instane
    public init() {}
}
extension PersistentStorageImpl: PersistentState.Storage {
    public func list() -> [String] {
        [String](self.entries.keys)
    }
    public func read<S: StringProtocol>(_ key: S) -> Data? {
        self.entries[String(key)]
    }
    public func write<S: StringProtocol, D: DataProtocol>(_ key: S, value: D) throws {
        self.entries[String(key)] = Data(value)
    }
    public func delete<S: StringProtocol>(_ key: S) {
        self.entries[String(key)] = nil
    }
}


/// A global shared `Storage` implementation
public class StorageImpl {
    /// The storage entries
    private static var entries: RwLock<[String: Data]> = RwLock([:])
    /// Checks whether the storage is empty
    public static var isEmpty: Bool {
        Self.entries.read({ $0.isEmpty })
    }
    
    /// Creates a new `StorageImpl` instane
    public init() {}
    
    /// Fails randomly to simulate errors
    @inline(__always) private func testError(probability: Double) throws {
        if Bool.random(probability: probability) {
            throw StorageError.syntheticError()
        }
    }
}
extension StorageImpl: StorageP2P.Storage {
    public func list() throws -> [String] {
        try self.testError(probability: Config.pError)
        return Self.entries.read({ [String]($0.keys) })
    }
    public func read<S: StringProtocol>(name: S) throws -> Data {
        try self.testError(probability: Config.pError)
        return try Self.entries.read({
            try $0[String(name)] ?? { throw StorageError.noSuchEntry() }()
        })
    }
    public func write<S: StringProtocol>(name: S, data: Data) throws {
        try self.testError(probability: Config.pError / 2)
        Self.entries.write({ $0[String(name)] = data })
        try self.testError(probability: Config.pError / 2)
    }
    public func delete<S: StringProtocol>(name: S) throws {
        try self.testError(probability: Config.pError / 2)
        Self.entries.write({ $0[String(name)] = nil })
        try self.testError(probability: Config.pError / 2)
    }
}
