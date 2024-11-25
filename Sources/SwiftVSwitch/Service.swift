import SwiftLinkedListAndHash
import VProxyCommon

public class Service {
    public private(set) var proto: UInt8
    public private(set) var vip: any IP
    public private(set) var port: UInt16
    public private(set) var destsV4 = [IPv4Port: Dest]()
    public private(set) var destsV6 = [IPv6Port: Dest]()
    public private(set) var dests = [Dest]()
    public private(set) var sched: DestScheduler
    public private(set) var localipv4: IPPool
    public private(set) var localipv6: IPPool
    public var statistics = ServiceStatistics()
    public var connList = LinkedList<ConnectionServiceListNode>()

    public convenience init(proto: UInt8, vip: any IP, port: UInt16, sched: DestScheduler,
                            totalWorkerCount: Int, currentWorkerIndex: Int)
    {
        let powerOf2 = Utils.findNextPowerOf2(totalWorkerCount)
        let portMask = UInt16((~(powerOf2 - 1)) & 0xffff)
        self.init(proto: proto, vip: vip, port: port, sched: sched, portMask: portMask, portFill: UInt16(currentWorkerIndex + 1))
    }

    public init(proto: UInt8, vip: any IP, port: UInt16, sched: DestScheduler,
                portMask: UInt16, portFill: UInt16)
    {
        self.proto = proto
        self.vip = vip
        self.port = port
        self.sched = sched
        localipv4 = IPPool(portMask: portMask, portFill: portFill)
        localipv6 = IPPool(portMask: portMask, portFill: portFill)

        connList.selfInit()
        self.sched.initWith(svc: self)
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

        if let v4 = dest.ip as? IPv4 {
            let key = IPv4Port(v4, dest.port)
            destsV4[key] = dest
        } else if let v6 = dest.ip as? IPv6 {
            let key = IPv6Port(v6, dest.port)
            destsV6[key] = dest
        }

        dests.append(dest)
        sched.updateFor(svc: self)
        return true
    }

    public func removeDest(ip: any IP, port: UInt16) -> Bool {
        for (index, d) in dests.enumerated() {
            if d.ip.equals(ip) && d.port == port {
                dests.remove(at: index)
                return true
            }
        }
        if let v4 = ip as? IPv4 {
            let key = IPv4Port(v4, port)
            destsV4.removeValue(forKey: key)
        } else if let v6 = ip as? IPv6 {
            let key = IPv6Port(v6, port)
            destsV6.removeValue(forKey: key)
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

    public func lookupDest(ip: any IP, port: UInt16) -> Dest? {
        if let v4 = ip as? IPv4 {
            let key = IPv4Port(v4, port)
            return destsV4[key]
        } else if let v6 = ip as? IPv6 {
            let key = IPv6Port(v6, port)
            return destsV6[key]
        }
        return nil // will not reach here
    }

    public func recordConn(_ conn: Connection) {
        conn.node.addInto(list: &connList)
        ENSURE_REFERENCE_COUNTED(conn)
    }

    public func destroy() {
        connList.destroy()
    }
}

public struct ServiceStatistics: Encodable, Decodable {
    public var addressBusyCount: UInt64 = 0

    public init() {}

    public mutating func inc(_ another: ServiceStatistics) {
        addressBusyCount += another.addressBusyCount
    }
}

public class Dest {
    public private(set) var ip: any IP
    public private(set) var port: UInt16
    public private(set) var service: Service
    public private(set) var weight: Int
    public private(set) var fwd: FwdMethod
    public var statistics = DestStatistics()

    public init(_ ip: any IP, _ port: UInt16, service: Service, weight: Int, fwd: FwdMethod) {
        self.ip = ip
        self.port = port
        self.service = service
        self.weight = weight
        self.fwd = fwd
    }
}

public struct DestStatistics: Encodable, Decodable {
    public var activeConns = 0
    public var inactiveConns = 0

    public init() {}

    public mutating func inc(_ stats: DestStatistics) {
        activeConns += stats.activeConns
        inactiveConns += stats.inactiveConns
    }
}

public enum FwdMethod: UInt8 {
    case FNAT
    // TODO: support other fwd methods
}

public class IPPool {
    public private(set) var ips = [any IP]()
    public private(set) var portMask: UInt16
    public private(set) var portFill: UInt16
    public var offset = 0

    public init(portMask: UInt16, portFill: UInt16) {
        self.portMask = portMask
        self.portFill = portFill
    }

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
