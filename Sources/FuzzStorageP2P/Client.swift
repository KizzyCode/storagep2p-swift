import Foundation
import StorageP2P
import ValueProvider


/// Generates deterministic test messages
private struct Message {
    /// Generates the deterministic test message for `sender->receiver:ctr`
    public static func create(sender: UniqueID, receiver: UniqueID, counter: UInt64) -> Data {
        "sender: \(sender.bytes), receiver: \(receiver.bytes), counter: \(counter)".data(using: .utf8)!
    }
}


/// A "persistent" connection state
public struct ConnectionState {
    /// The states
    private var states: [ConnectionID: StateObject] = [:]
}
extension ConnectionState: MappedDictionary {
    public typealias Key = ConnectionID
    public typealias Value = StateObject
    
    public func list() -> Set<ConnectionID> {
        Set(self.states.keys)
    }
    public func load() -> [ConnectionID: StateObject] {
        self.states
    }
    public func load(key: ConnectionID) -> StateObject? {
        self.states[key]
    }
    public mutating func load(key: ConnectionID, default: StateObject) -> StateObject {
        if self.states[key] == nil {
            self.states[key] = `default`
        }
        return self.states[key]!
    }
    public mutating func store(key: ConnectionID, value: StateObject?) {
        self.states[key] = value
    }
    public mutating func delete() {
        fatalError("Deletion is not supported")
    }
    
    /// `self` as `AnyMappedDictionary`
    public var asAny: AnyMappedDictionary<Key, Value> {
        AnyMappedDictionary(self)
    }
}


/// A client for fuzzing
public class Client {
    /// The `storage_p2p` ID of this client
    public let id: UniqueID = UniqueID()
    /// The peer connection IDs to fuzz together with the associated RX and TX counters
    public var state = ConnectionState().asAny
    
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
        for conn in self.state.keys.filter({ $0.local == self.id }) {
            for _ in 0 ..< Int.random(in: 0 ..< 7) {
                autoreleasepool(invoking: {
                    // Generate deterministic message
                    let message = Message.create(sender: self.id, receiver: conn.remote,
                                                 counter: self.state[conn]!.tx)
                    
                    // Send message
                    let sender = Sender(connection: conn, state: self.state, storage: StorageImpl())
                    retry({ try sender.send(message: message) })
                })
            }
        }
    }
    /// Receives all pending messages for all connections
    public func receive() {
        for conn in self.state.keys.filter({ $0.local == self.id }) {
            autoreleasepool(invoking: {
                // Create the receiver
                let receiver = Receiver(connection: conn, state: self.state, storage: StorageImpl())
                
                // Receive all pending messages
                while let peeked = retry({ try receiver.peek(nth: 0) }) {
                    // Generate expected message
                    let expected = Message.create(sender: conn.remote, receiver: self.id,
                                                  counter: self.state[conn]!.rx)
                    
                    // Validate the peeked message
                    assert(peeked == expected, "Unexpected message: expected ",
                           String(data: expected, encoding: .utf8)!, ", got: ", String(data: peeked, encoding: .utf8)!)
                    
                    // Receive and validate message
                    let received = retry({ try receiver.receive() })
                    assert(received == expected, "Unexpected message: expected ",
                           String(data: expected, encoding: .utf8)!, ", got: ",
                           String(data: received ?? Data([0x6E, 0x69, 0x6C]), encoding: .utf8)!)
                }
                
                // Perform a garbage collection
                retry({ try receiver.gc() })
            })
        }
    }
}
