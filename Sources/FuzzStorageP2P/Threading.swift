import Foundation


/// A wrapper to guarantee threadsafe synchronized access to the underlying value
public class RwLock<T> {
	/// The queue to synchronize access to the value
    private let queue = DispatchQueue(label: "RwLock.GlobalQueue.concurrent", attributes: .concurrent)
	/// The wrapped value
	private var value: T
	
	/// Creates a new atomic
	public init(_ value: T) {
		self.value = value
	}
	
    /// Provides shared read-only access to the underlying value
    public func read<R>(_ access: (T) throws -> R) rethrows -> R {
        try self.queue.sync(execute: { try access(self.value) })
    }
	/// Provides exclusive write access to the underlying value
	public func write<R>(_ access: (inout T) throws -> R) rethrows -> R {
        try self.queue.sync(flags: .barrier, execute: { try access(&self.value) })
	}
}


/// A joinable thread
public class Thread<T> {
    /// The signal when the thread is done
	private var semaphore = DispatchSemaphore(value: 0)
    /// The result var
	private var result: T! = nil
	
	/// Executes `block` in a new thread
	public init(run block: @escaping () -> T) {
		DispatchQueue.global().async(execute: {
			self.result = block()
			self.semaphore.signal()
		})
	}
	
	/// Joins the thread
	public func join() -> T {
		self.semaphore.wait()
		return self.result!
	}
}
