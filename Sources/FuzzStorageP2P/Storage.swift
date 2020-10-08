import Foundation
import StorageP2P


/// An filesystem related error
public enum StorageError: Error {
    /// A synthetic error for testing
    case syntheticError(StaticString = "A synthetic error for testing", StaticString = #file, Int = #line)
    /// The requested entry does not exists
    case noSuchEntry(StaticString = "No such entry", StaticString = #file, Int = #line)
}


/// A global shared `Storage` implementation
public class StorageImpl {
    /// The storage entries
    private static var entries: RwLock<[Data: Data]> = RwLock([:])
    /// Checks whether the storage is empty
    public static var isEmpty: Bool {
        Self.entries.read({ $0.isEmpty })
    }
    
    /// Creates an accessor for the shared underlying storage
    public init() {}
    
    /// Fails randomly to simulate errors
    @inline(__always) private func testError(probability: Double) throws {
        if Bool.random(probability: probability) {
            throw StorageError.syntheticError()
        }
    }
}
extension StorageImpl: StorageP2P.MutableStorage {
    public func list() throws -> [Data] {
        try self.testError(probability: Config.pError)
        return Self.entries.read({ [Data]($0.keys) })
    }
    public func read<D: DataProtocol>(name: D) throws -> Data {
        try self.testError(probability: Config.pError)
        return try Self.entries.read({
            try $0[Data(name)] ?? { throw StorageError.noSuchEntry() }()
        })
    }
    public func write<D: DataProtocol>(name: D, data: Data) throws {
        try self.testError(probability: Config.pError / 2)
        Self.entries.write({ $0[Data(name)] = data })
        try self.testError(probability: Config.pError / 2)
    }
    public func delete<D: DataProtocol>(name: D) throws {
        try self.testError(probability: Config.pError / 2)
        Self.entries.write({ $0[Data(name)] = nil })
        try self.testError(probability: Config.pError / 2)
    }
}
