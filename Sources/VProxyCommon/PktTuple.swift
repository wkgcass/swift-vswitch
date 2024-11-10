public struct PktTuple: Hashable {
    public var proto: UInt8
    public var ud8: UInt8
    public var srcPort: UInt16
    public var dstPort: UInt16
    public var ud16x1: UInt16
    public var srcIp: any IP
    public var dstIp: any IP
    public var ud64: UInt64
    public var ud32x1: UInt32
    public var ud16x2: UInt16
    public var ud16x3: UInt16

    public init(proto: UInt8,
                srcPort: UInt16,
                dstPort: UInt16,
                srcIp: any IP,
                dstIp: any IP)
    {
        assert((srcIp is IPv4 && dstIp is IPv4) || (srcIp is IPv6 && dstIp is IPv6))
        self.proto = proto
        ud8 = 0
        self.srcPort = srcPort
        self.dstPort = dstPort
        ud16x1 = 0
        self.srcIp = srcIp
        self.dstIp = dstIp
        ud64 = 0
        ud32x1 = 0
        ud16x2 = 0
        ud16x3 = 0
    }

    public var isIPv6: Bool {
        return srcIp is IPv6
    }

    public var isIPv4: Bool {
        return srcIp is IPv4
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(proto)
        hasher.combine(ud8)
        hasher.combine(srcPort)
        hasher.combine(dstPort)
        hasher.combine(ud16x1)
        hasher.combine(srcIp)
        hasher.combine(dstIp)
        hasher.combine(ud64)
        hasher.combine(ud32x1)
        hasher.combine(ud16x2)
        hasher.combine(ud16x3)
    }

    public static func == (lhs: PktTuple, rhs: PktTuple) -> Bool {
        return lhs.proto == rhs.proto && lhs.ud8 == rhs.ud8 &&
            lhs.srcPort == rhs.srcPort && lhs.dstPort == rhs.dstPort &&
            lhs.srcIp.equals(rhs.srcIp) && lhs.dstIp.equals(rhs.dstIp) &&
            lhs.ud16x1 == rhs.ud16x1 && lhs.ud16x2 == rhs.ud16x2 && lhs.ud16x3 == rhs.ud16x3 &&
            lhs.ud32x1 == rhs.ud32x1
    }
}
