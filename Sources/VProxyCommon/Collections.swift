import Collections

public class ConcurrentQueue<E> {
    private var queue = Deque<E>()
    private let lock = Lock()

    public init() {}

    public func isEmpty() -> Bool {
        return count == 0
    }

    public func push(_ e: E) {
        lock.lock()
        queue.append(e)
        lock.unlock()
    }

    public func pop() -> E? {
        lock.lock()
        defer { lock.unlock() }
        return queue.popFirst()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return queue.count
    }
}
