import Foundation
import StorageP2P


/// Generates deterministic test messages
private struct Message {
    /// Generates the deterministic test message for `sender->receiver:ctr`
    public static func create(sender: UniqueID, receiver: UniqueID, counter: UInt64) -> Data {
        "sender: \(sender.bytes), receiver: \(receiver.bytes), counter: \(counter)".data(using: .utf8)!
    }
}


/// A SP2P counter
public class Counter: ValueProvider<UInt64> {
    /// The real value
    private var _value: UInt64
    
    /// Creates a new counter
    ///
    ///  - Parameter value: The initial value
    public init(_ value: UInt64 = 0) {
        self._value = value
        super.init()
    }
    
    override public func load() throws -> UInt64 {
        self._value
    }
    override public func store(_ newValue: UInt64) throws {
        self._value = newValue
    }
}


/// A client for fuzzing
public class Client {
    /// The `storage_p2p` ID of this client
    public let local: UniqueID = UniqueID()
    /// The peer connection IDs to fuzz together with the associated RX and TX counters
    public var peers: [(conn: ConnectionID, rx: Counter, tx: Counter)] = []
    
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
        for peer in self.peers.indices {
            for _ in 0 ..< Int.random(in: 0 ..< 7) {
                autoreleasepool(invoking: {
                    // Generate deterministic message
                    let message = Message.create(sender: self.peers[peer].conn.local,
                                                 receiver: self.peers[peer].conn.remote,
                                                 counter: self.peers[peer].tx.value)
                    
                    // Send message
                    let sender = Sender(id: self.peers[peer].conn, at: self.peers[peer].tx, storage: StorageImpl())
                    retry({ try sender.send(message: message) })
                })
            }
        }
    }
    /// Receives all pending messages for all connections
    public func receive() {
        for peer in self.peers.indices {
            autoreleasepool(invoking: {
                // Create the receiver
                let receiver = Receiver(id: self.peers[peer].conn, at: self.peers[peer].rx, storage: StorageImpl())
                
                // Receive all pending messages
                while let peeked = retry({ try receiver.peek(nth: 0) }) {
                    // Generate expected message
                    let expected = Message.create(sender: self.peers[peer].conn.remote,
                                                  receiver: self.peers[peer].conn.local,
                                                  counter: self.peers[peer].rx.value)
                    
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
