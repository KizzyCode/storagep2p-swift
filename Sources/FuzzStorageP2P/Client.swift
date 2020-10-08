import Foundation
import StorageP2P


public typealias UUID = StorageP2P.UUID


/// Generates deterministic test messages
private struct Message {
    /// Generates the deterministic test message for `sender->receiver:ctr`
    public static func create(sender: UUID, receiver: UUID, counter: UInt64) -> Data {
        "sender: \(sender.bytes), receiver: \(receiver.bytes), counter: \(counter)".data(using: .utf8)!
    }
}


/// A client for fuzzing
public class Client {
    /// The underlying socket
    private let socket = Socket(state: StateImpl(), storage: StorageImpl())
    /// The `storage_p2p` address of this client
    public let local: UUID = UUID()
    /// The peer connection IDs to fuzz together with the associated RX and TX counters
    public var peers: [(conn: ConnectionID, rx: UInt64, tx: UInt64)] = []
    
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
                                                 counter: self.peers[peer].tx)
                
                    // Send message
                    retry({ try self.socket.send(conn: self.peers[peer].conn, message: message) })
                    self.peers[peer].tx += 1
                })
            }
        }
    }
    /// Receives all pending messages for all connections
    public func receive() {
        for peer in self.peers.indices {
            autoreleasepool(invoking: {
                // Get connection and receive messages
                while retry({ try self.socket.canReceive(conn: self.peers[peer].conn) }) {
                    // Generate expected message
                    let expected = Message.create(sender: self.peers[peer].conn.remote,
                                                  receiver: self.peers[peer].conn.local, counter: self.peers[peer].rx)
                    
                    // Peek at and validate the message
                    var message = retry({ try self.socket.peek(conn: self.peers[peer].conn, nth: 0) })!
                    assert(message == expected, "Unexpected message: expected ",
                           String(data: expected, encoding: .utf8)!, ", got: ", String(data: message, encoding: .utf8)!)
                    
                    // Receive and validate message
                    message = retry({ try self.socket.receive(conn: self.peers[peer].conn) })
                    assert(message == expected, "Unexpected message: expected ",
                           String(data: expected, encoding: .utf8)!, ", got: ", String(data: message, encoding: .utf8)!)
                    self.peers[peer].rx += 1
                }
                
                // Perform a garbage collection
                retry({ try self.socket.gc(conn: self.peers[peer].conn) })
            })
        }
    }
}
