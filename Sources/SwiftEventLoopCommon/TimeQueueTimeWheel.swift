#if !USE_TIMEQUEUE
import SwiftLinkedListAndHash
import VProxyCommon

class TimeQueue {
#if DEBUG
    var wheel = TimeWheel<TimeElemNode>(currentTimeMillis: OS.currentTimeMillis(), precisionMillis: 10, levelTicks: 1000, 1000, 1001)
#else
    var wheel = TimeWheel<TimeElemNode>(currentTimeMillis: OS.currentTimeMillis(), precisionMillis: 500, levelTicks: 1000, 1000, 1001)
#endif

    public func add(currentTimeMillis: Int64, timeoutMillis: Int, elem: Runnable) -> TimeElem {
        let event = TimeElem(currentTimeMillis + Int64(timeoutMillis), elem, self)
        let ok = event.node.addInto(wheel: &wheel)
        if ok {
            ENSURE_REFERENCE_COUNTED(event)
        } else {
            Logger.error(.IMPROPER_USE, "trying to add timer event with trigger time \(event.node.triggerTime), which cannot fit into the timewheel")
        }
        return event
    }

    public func poll(currentTimeMillis: Int64) -> LinkedListRef<TimeElemNode> {
        return wheel.poll(currentTimeMillis: currentTimeMillis)
    }

    public func nextTime(currentTimeMillis: Int64) -> Int {
#if DEBUG
        let next = wheel.nextTimeAccurate()
#else
        let next = wheel.nextTimeFast()
#endif
        if next != Int64.max {
            return Int(next - currentTimeMillis)
        } else {
            return Int.max
        }
    }

    deinit {
        wheel.destroy()
    }
}

class TimeElem: Comparable {
    public var node = TimeElemNode()
    public let elem: Runnable
    private let queue: TimeQueue

    init(_ triggerTime: Int64, _ elem: Runnable, _ queue: TimeQueue) {
        node.triggerTime = triggerTime
        self.elem = elem
        self.queue = queue
    }

    public func get() -> Runnable {
        return elem
    }

    public func removeSelf() {
        node.removeSelf()
    }

    public static func < (lhs: TimeElem, rhs: TimeElem) -> Bool {
        return lhs.node.triggerTime < rhs.node.triggerTime
    }

    public static func == (lhs: TimeElem, rhs: TimeElem) -> Bool {
        return lhs === rhs
    }
}

struct TimeElemNode: SwiftLinkedListAndHash.TimeNode {
    typealias V = TimeElem

    var vars = SwiftLinkedListAndHash.LinkedListNodeVars()
    var triggerTime: Int64 = 0
    init() {}
    static let fieldOffset: Int = 0
}
#endif
