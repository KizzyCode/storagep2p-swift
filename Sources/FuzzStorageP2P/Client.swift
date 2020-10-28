import Foundation
import StorageP2P


/// Generates deterministic test messages
private struct Message {
    /// Generates the deterministic test message for `sender->receiver:ctr`
    public static func create(sender: UniqueID, receiver: UniqueID, counter: UInt64) -> Data {
        "sender: \(sender.bytes), receiver: \(receiver.bytes), counter: \(counter)".data(using: .utf8)!
    }
}


/// A "persistent" connection state
public struct ConnectionStatesImpl {
    /// The states
    private var states: [ConnectionID: ConnectionStateObject] = [:]
}
extension ConnectionStatesImpl: MutableConnectionStates {
    public func list() -> Set<ConnectionID> {
        Set(self.states.keys)
    }
    public func load(connection: ConnectionID) -> ConnectionStateObject {
        return self.states[connection]!
    }
    public mutating func store(connection: ConnectionID, state: ConnectionStateObject?) {
        self.states[connection] = state
    }
    public mutating func delete() {
        fatalError("Deletion is not supported")
    }
}


/// A client for fuzzing
public class Client {
    /// The `storage_p2p` ID of this client
    public let id: UniqueID = UniqueID()
    /// The peer connection IDs to fuzz together with the associated RX and TX counters
    public var state = ConnectionStatesImpl()
    
    /// Creates a new fuzzing client
    public init() {}
    
    /// Starts a fuzzing sequence
    public func fuzz() {
        for _ in 0 ..< Config.fuzzIterations {
            self.send()
            self.receive()
            stdout(".")
        }
    }
    
    /// Sends a random amount of messages to all connections
    public func send() {
        for connectionID in self.state.list().filter({ $0.local == self.id }) {
            for _ in 0 ..< Int.random(in: 0 ..< 7) {
                autoreleasepool(invoking: {
                    // Generate deterministic message
                    let message = Message.create(sender: self.id, receiver: connectionID.remote,
                                                 counter: self.state.load(connection: connectionID).tx)
                    
                    // Send message
                    let connection = Connection(id: connectionID, states: self.state, storage: StorageImpl())
                    retry({ try connection.send(message: message) })
                })
            }
        }
    }
    /// Receives all pending messages for all connections
    public func receive() {
        for connectionID in self.state.list().filter({ $0.local == self.id }) {
            autoreleasepool(invoking: {
                // Create the receiver
                let connection = Connection(id: connectionID, states: self.state, storage: StorageImpl())
                
                // Receive all pending messages
                while let peeked = retry({ try connection.peek(nth: 0) }) {
                    // Generate expected message
                    let expected = Message.create(sender: connectionID.remote, receiver: self.id,
                                                  counter: self.state.load(connection: connectionID).rx)
                    
                    // Validate the peeked message
                    assert(peeked == expected, "Unexpected message: expected ",
                           String(data: expected, encoding: .utf8)!, ", got: ", String(data: peeked, encoding: .utf8)!)
                    
                    // Receive and validate message
                    let received = retry({ try connection.receive() })
                    assert(received == expected, "Unexpected message: expected ",
                           String(data: expected, encoding: .utf8)!, ", got: ",
                           String(data: received, encoding: .utf8)!)
                }
                
                // Perform a garbage collection
                retry({ try connection.gc() })
            })
        }
    }
}
