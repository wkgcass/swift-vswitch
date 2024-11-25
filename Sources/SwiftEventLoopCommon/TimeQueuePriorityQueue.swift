#if USE_TIMEQUEUE
import SwiftPriorityQueue

class TimeQueue {
    var queue: PriorityQueue<TimeElem> = PriorityQueue(ascending: true)

    public func add(currentTimeMillis: Int64, timeoutMillis: Int, elem: Runnable) -> TimeElem {
        let event = TimeElem(currentTimeMillis + Int64(timeoutMillis), elem, self)
        queue.push(event)
        return event
    }

    public func poll() -> Runnable? {
        let elem = queue.pop()
        guard let elem else {
            return nil
        }
        return elem.elem
    }

    public func isEmpty() -> Bool {
        return queue.isEmpty
    }

    public func nextTime(currentTimeMillis: Int64) -> Int {
        let elem = queue.peek()
        guard let elem else {
            return Int.max
        }
        let triggerTime = elem.triggerTime
        return Int(max(triggerTime - currentTimeMillis, 0))
    }
}

class TimeElem: Comparable {
    public let triggerTime: Int64
    public let elem: Runnable
    private let queue: TimeQueue

    init(_ triggerTime: Int64, _ elem: Runnable, _ queue: TimeQueue) {
        self.triggerTime = triggerTime
        self.elem = elem
        self.queue = queue
    }

    public func get() -> Runnable {
        return elem
    }

    public func removeSelf() {
        queue.queue.remove(self)
    }

    public static func < (lhs: TimeElem, rhs: TimeElem) -> Bool {
        return lhs.triggerTime < rhs.triggerTime
    }

    public static func == (lhs: TimeElem, rhs: TimeElem) -> Bool {
        return lhs === rhs
    }
}
#endif
