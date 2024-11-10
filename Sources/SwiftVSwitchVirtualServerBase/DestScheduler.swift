public protocol DestScheduler {
    var name: String { get }
    var fullname: String { get }
    mutating func schedule(svc: Service) -> Dest?
    mutating func update()
}

public struct RoundRobinDestScheduler: DestScheduler {
    public nonisolated(unsafe) static let instance = RoundRobinDestScheduler()

    private var offset: Int = 0
    public let name = "rr"
    public let fullname = "roundrobin"

    private init() {}

    public mutating func schedule(svc: Service) -> Dest? {
        let dests = svc.dests
        if dests.isEmpty {
            return nil
        }

        var oldOff = offset
        if oldOff >= dests.count {
            oldOff = offset % dests.count
            offset = oldOff
        }
        while true {
            let ret = dests[offset % dests.count]
            offset += 1
            if ret.weight != 0 {
                return ret
            }
            if offset >= dests.count {
                offset = 0
            }
            if offset == oldOff {
                // no valid dest found
                return nil
            }
        }
    }

    public mutating func update() {
        // no need to update
    }
}
