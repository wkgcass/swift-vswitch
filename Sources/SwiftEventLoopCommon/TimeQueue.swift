import SwiftPriorityQueue

public protocol TimeQueue<T>: AnyObject {
    associatedtype T

    func add(currentTimeMillis: Int64, timeoutMillis: Int, elem: T) -> any TimeElem<T>
    func poll() -> T?
    func isEmpty() -> Bool
    func nextTime(currentTimeMillis: Int64) -> Int
}

public protocol TimeElem<T>: AnyObject {
    associatedtype T

    func get() -> T
    func removeSelf()
}

class TimeQueueImpl<T>: TimeQueue {
    var queue: PriorityQueue<TimeElemImpl<T>> = PriorityQueue(ascending: true)

    public func add(currentTimeMillis: Int64, timeoutMillis: Int, elem: T) -> any TimeElem<T> {
        let event = TimeElemImpl(currentTimeMillis + Int64(timeoutMillis), elem, self)
        queue.push(event)
        return event
    }

    public func poll() -> T? {
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

class TimeElemImpl<T>: TimeElem, Comparable {
    public let triggerTime: Int64
    public let elem: T
    private let queue: TimeQueueImpl<T>

    init(_ triggerTime: Int64, _ elem: T, _ queue: TimeQueueImpl<T>) {
        self.triggerTime = triggerTime
        self.elem = elem
        self.queue = queue
    }

    public func get() -> T {
        return elem
    }

    public func removeSelf() {
        queue.queue.remove(self)
    }

    public static func < (lhs: TimeElemImpl<T>, rhs: TimeElemImpl<T>) -> Bool {
        return lhs.triggerTime < rhs.triggerTime
    }

    public static func == (lhs: TimeElemImpl<T>, rhs: TimeElemImpl<T>) -> Bool {
        return lhs === rhs
    }
}
