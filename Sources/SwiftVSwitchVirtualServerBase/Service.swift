import VProxyCommon

public class Service {
    public private(set) var proto: UInt8
    public private(set) var vip: any IP
    public private(set) var port: UInt16
    public private(set) var dests = [Dest]()
    public private(set) var sched: DestScheduler
    public private(set) var localipv4 = IPPool()
    public private(set) var localipv6 = IPPool()

    public init(proto: UInt8, vip: any IP, port: UInt16, sched: DestScheduler) {
        self.proto = proto
        self.vip = vip
        self.port = port
        self.sched = sched
    }

    public func schedule() -> Dest? {
        return sched.schedule(svc: self)
    }

    public func addDest(_ dest: Dest) -> Bool {
        for d in dests {
            if d.ip.equals(dest.ip) && d.port == dest.port {
                return false
            }
        }

        dests.append(dest)
        sched.update()
        return true
    }

    public func removeDest(ip: any IP, port: UInt16) -> Bool {
        for (index, d) in dests.enumerated() {
            if d.ip.equals(ip) && d.port == port {
                dests.remove(at: index)
                return true
            }
        }
        return false
    }

    public func addLocalIP(_ ip: any IP) -> Bool {
        if let _ = ip as? IPv4 {
            return localipv4.add(ip)
        } else {
            let _ = ip as? IPv6
            return localipv6.add(ip)
        }
    }
}

public class Dest {
    public private(set) var ip: any IP
    public private(set) var port: UInt16
    public private(set) var service: Service
    public private(set) var weight: UInt8
    public private(set) var fwd: FwdMethod

    public init(_ ip: any IP, _ port: UInt16, service: Service, weight: UInt8, fwd: FwdMethod) {
        self.ip = ip
        self.port = port
        self.service = service
        self.weight = weight
        self.fwd = fwd
    }
}

public enum FwdMethod: UInt8 {
    case FNAT
    // TODO: support other fwd methods
}

public class IPPool {
    public private(set) var ips = [any IP]()
    public private(set) var portMask: UInt16 = 0xffff
    public var offset = 0

    init() {}

    public func add(_ ip: any IP) -> Bool {
        for i in ips {
            if i.equals(ip) {
                return false
            }
        }
        ips.append(ip)
        return true
    }

    public func remove(_ ip: any IP) -> Bool {
        for (index, i) in ips.enumerated() {
            if i.equals(ip) {
                ips.remove(at: index)
                return true
            }
        }
        return false
    }
}
