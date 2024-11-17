public protocol DestScheduler {
    var name: String { get }
    var fullname: String { get }
    mutating func schedule(svc: Service) -> Dest?
    mutating func initWith(svc: Service)
    mutating func updateFor(svc: Service)
}

public struct RoundRobinDestScheduler: DestScheduler {
    private var offset: Int = 0
    public let name = "rr"
    public let fullname = "roundrobin"

    public init() {}

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

    public func initWith(svc _: Service) {
        // no need to init
    }

    public mutating func updateFor(svc _: Service) {
        // no need to update
    }
}

public struct WeightedRoundRobinDestScheduler: DestScheduler {
    public let name = "wrr"
    public let fullname = "weighted-roundrobin"

    var cl: Int = -1 /* current list head */
    var cw: Int = 0 /* current weight */
    var mw: Int = 0 /* maximum weight */
    var di: Int = 0 /* decreasing interval */

    public init() {}

    public mutating func schedule(svc: Service) -> Dest? {
        let dests = svc.dests
        if dests.isEmpty {
            return nil
        }

        let p = cl
        while true {
            if cl == -1 {
                cl = 0
                cw -= di
                if cw <= 0 {
                    cw = mw
                    if cw == 0 {
                        cl = -1
                        return nil
                    }
                }
            } else {
                cl += 1; if cl >= dests.count { cl = -1 }
            }

            if cl != -1 {
                let ret = dests[cl]
                if ret.weight >= cw {
                    return ret
                }
            }

            if cl == p && cw == di {
                return nil
            }
        }
    }

    public mutating func initWith(svc: Service) {
        cl = svcRandFirstDest(svc)
        cw = 0
        mw = maxWeight(svc)
        di = svcGcdWeight(svc)
    }

    public mutating func updateFor(svc: Service) {
        cl = svcRandFirstDest(svc)
        mw = maxWeight(svc)
        di = svcGcdWeight(svc)
        if cw > mw {
            cw = 0
        }
    }

    private func maxWeight(_ svc: Service) -> Int {
        let dests = svc.dests
        var max = 0
        for d in dests {
            if d.weight > max {
                max = d.weight
            }
        }
        return max
    }
}

func svcRandFirstDest(_ svc: Service) -> Int {
    let dests = svc.dests
    if dests.isEmpty {
        return -1
    }
    return Int.random(in: 0 ..< dests.count)
}

func svcGcdWeight(_ svc: Service) -> Int {
    var g = 0
    for dest in svc.dests {
        let weight = dest.weight
        if weight > 0 {
            if g > 0 {
                g = gcd(weight, g)
            } else {
                g = weight
            }
        }
    }
    return g != 0 ? g : 1
}

func gcd(_ a: Int, _ b: Int) -> Int {
    var a = a
    var b = b
    while a != b {
        if a > b {
            a = a - b
        } else {
            b = b - a
        }
    }
    return a
}
