import Collections
import WaitfreeMpscQueue

public class ConcurrentQueue<E: AnyObject> {
    private var queue = mpscq()

    public init() {
        mpscq_create(&queue, 2 << 18)
    }

    public func push(_ e: E) {
        let ptr = Unsafe.convertToNativeAddRef(e)
        if !mpscq_enqueue(&queue, ptr) {
            Logger.warn(.ALERT, "failed to enqueue to ConcurrentQueue")
            Unmanaged<E>.fromOpaque(ptr).release()
        }
    }

    public func pop() -> E? {
        let ptr = mpscq_dequeue(&queue)
        guard let ptr else {
            return nil
        }
        let e: E = Unsafe.convertFromNativeDecRef(ptr)
        return e
    }

    public var count: Int {
        return mpscq_count(&queue)
    }

    public func isEmpty() -> Bool { count == 0 }

    deinit {
        mpscq_destroy(&queue)
    }
}
