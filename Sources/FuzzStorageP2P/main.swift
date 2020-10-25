import Foundation
import StorageP2P


/// The config options for fuzzing
public struct Config {
    /// The randomness precision
    static let randomPrecision = 1_000_000_000
    /// The error probability
    static let pError = 0.1
    /// The retry interval in milliseconds
    static let retryIntervalMS = 37
    /// The amount of client threads to spawn
    static let threadCount = 23
    /// The fuzz iterations per thread until a validation is performed
    static let fuzzIterations = 167
    /// The amount of fuzzing rounds (i.e. the amount of `fuzzIterations * threadCount -> finish -> verify` rounds)
    static let fuzzRounds = 4
}


// Implement a `random` function for bools
public extension Bool {
    /// Creates a random boolean with a `probability` for `true` where `probability` ranges from `0` to `1`
    static func random(probability: Double) -> Self {
        let randomPrecision = 1_000_000_000
        return Int.random(in: 0 ..< randomPrecision) < Int(probability * Double(randomPrecision))
    }
}


/// Retries `f` until it succeeds
public func retry<R>(_ block: () throws -> R) -> R {
    while true {
        do {
            return try block()
        } catch {
            usleep(UInt32(Config.retryIntervalMS) * 1000)
        }
    }
}


/// Asserts a condition
@inline(__always)
public func assert(_ block: @autoclosure () -> Bool, _ message: String..., file: StaticString = #file,
                   line: Int = #line) {
    guard block() else {
        let message = "\(message.joined()) @\(file):\(line)".data(using: .utf8)!
        _ = message.withUnsafeBytes({ fwrite($0.baseAddress!, 1, $0.count, stdout) })
        fflush(stdout)
        abort()
    }
}


/// Prints to `stdout` without newline and flushes afterwards
@inline(__always)
public func stdout(_ string: StaticString) {
    fwrite(string.utf8Start, 1, string.utf8CodeUnitCount, stdout)
    fflush(stdout)
}
/// Prints to `stdout` without newline and flushes afterwards
@inline(__always)
public func stdout(string: String) {
    string.bytes.withUnsafeBytes({
        fwrite($0.baseAddress!, 1, $0.count, stdout)
        fflush(stdout)
    })
}


/// Performs the fuzzing
func fuzz() {
    // Create connections and collect all IDs
    let clients = (0 ..< Config.threadCount).map({ _ in Client() })
    let ids = clients.map({ $0.id })

    // Set peers
    clients.forEach({ client in
        ids.filter({ $0 != client.id })
            .map({ ConnectionID(local: client.id, remote: $0) })
            .forEach({ client.state[$0] = ConnectionState() })
    })

    // Start fuzzing
    for i in 1 ... Config.fuzzRounds {
        // Print the iteration information
        stdout(string: "\(i) of \(Config.fuzzRounds): ")
        
        // Start all fuzzing threads
        let threads: [Thread<()>] = clients.map({ client in
            defer { stdout("+") }
            return Thread(run: { client.fuzz() })
        })
        threads.forEach({
            $0.join()
            stdout("-")
        })
        
        // Perform a final receive and ensure that the storage is empty
        clients.forEach({
            $0.receive()
            stdout("*")
        })
        precondition(StorageImpl.isEmpty, "The storage is not empty")
        stdout("\n")
    }
}


// -- MARK: Main block

fuzz()
