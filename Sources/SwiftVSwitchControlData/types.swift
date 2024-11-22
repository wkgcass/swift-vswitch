import SwiftVSwitch
import Vapor

public struct Address: Content {
    public var ip: String
    public var mask: Int

    public init(ip: String, mask: Int) {
        self.ip = ip
        self.mask = mask
    }
}

public struct BridgeRef: Content {
    public var name: String
    public var id: UInt32
    public var interfaces: [String]

    public init(name: String, id: UInt32, interfaces: [String]) {
        self.name = name
        self.id = id
        self.interfaces = interfaces
    }
}

public struct NetstackRef: Content {
    public var name: String
    public var id: UInt32

    public init(name: String, id: UInt32) {
        self.name = name
        self.id = id
    }
}

public struct NetifFilter: Content {
    public var name: String?
    public init(name: String?) {
        self.name = name
    }
}

public struct NetifRef: Content {
    public var name: String
    public var id: UInt32
    public var addressesV4: [Address]
    public var addressesV6: [Address]
    public var mac: String
    public var statistics: IfaceStatistics

    public init(name: String, id: UInt32, addressesV4: [Address], addressesV6: [Address], mac: String, statistics: IfaceStatistics) {
        self.name = name
        self.id = id
        self.addressesV4 = addressesV4
        self.addressesV6 = addressesV6
        self.mac = mac
        self.statistics = statistics
    }
}

public struct NetifId: Content {
    public var name: String
    public var id: UInt32

    public init(name: String, id: UInt32) {
        self.name = name
        self.id = id
    }
}

public struct NeighborRef: Content {
    public var ip: String
    public var mac: String
    public var dev: NetifId
    public var timeout: Int

    public init(ip: String, mac: String, dev: NetifId, timeout: Int) {
        self.ip = ip
        self.mac = mac
        self.dev = dev
        self.timeout = timeout
    }
}

public struct RouteRef: Content {
    public var rule: String
    public var gateway: String?
    public var dev: NetifId
    public var src: String

    public init(rule: String, gateway: String? = nil, dev: NetifId, src: String) {
        self.rule = rule
        self.gateway = gateway
        self.dev = dev
        self.src = src
    }
}

public struct ServiceFilter: Content {
    public var proto: UInt8
    public var vip: String
    public var port: UInt16

    public init(proto: UInt8, vip: String, port: UInt16) {
        self.proto = proto
        self.vip = vip
        self.port = port
    }
}

public struct ServiceRef: Content {
    public var proto: UInt8
    public var vip: String
    public var port: UInt16
    public var dests: [DestRef]
    public var sched: String
    public var localipv4: [String]
    public var localipv6: [String]
    public var statistics: ServiceStatistics

    public init(proto: UInt8, vip: String, port: UInt16, dests: [DestRef], sched: String, localipv4: [String], localipv6: [String], statistics: ServiceStatistics) {
        self.proto = proto
        self.vip = vip
        self.port = port
        self.dests = dests
        self.sched = sched
        self.localipv4 = localipv4
        self.localipv6 = localipv6
        self.statistics = statistics
    }
}

public struct DestRef: Content {
    public var ip: String
    public var port: UInt16
    public var weight: Int
    public var fwd: String
    public var statistics: DestStatistics

    public init(ip: String, port: UInt16, weight: Int, fwd: String, statistics: DestStatistics) {
        self.ip = ip
        self.port = port
        self.weight = weight
        self.fwd = fwd
        self.statistics = statistics
    }
}

public final class ConnRef: Content {
    public var cid: Int
    public var proto: UInt8
    public var src: String
    public var srcPort: UInt16
    public var dst: String
    public var dstPort: UInt16
    public var state: String
    public var timeoutMillis: Int
    public var ttl: Int64
    public var isBeforeNat: Bool
    public var address: Int
    public var peer: ConnRef?

    public init(cid: Int,
                proto: UInt8, src: String, srcPort: UInt16, dst: String, dstPort: UInt16,
                state: String, timeoutMillis: Int, ttl: Int64,
                isBeforeNat: Bool, address: Int,
                peer: ConnRef?)
    {
        self.cid = cid
        self.proto = proto
        self.src = src
        self.srcPort = srcPort
        self.dst = dst
        self.dstPort = dstPort
        self.state = state
        self.timeoutMillis = timeoutMillis
        self.ttl = ttl
        self.isBeforeNat = isBeforeNat
        self.address = address
        self.peer = peer
    }
}

public struct RedirectCost: Content {
    public var redirectCount: Int64
    public var redirectCostUSecs: Int64
    public init(redirectCount: Int64, redirectCostUSecs: Int64) {
        self.redirectCount = redirectCount
        self.redirectCostUSecs = redirectCostUSecs
    }
}
