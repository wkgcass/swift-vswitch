public protocol CIDR: CustomStringConvertible, Hashable {
    var ip: any IP { get }
    var mask: any IP { get }
    var maskInt: Int { get }
    var network: any Network { get }
}

public extension CIDR {
    var description: String {
        return "\(ip)/\(maskInt)"
    }
}

public func GetCIDR(from: String) -> (any CIDR)? {
    let v4 = CIDRv4(from: from)
    if v4 != nil {
        return v4
    }
    return CIDRv6(from: from)
}

public struct CIDRv4: CIDR {
    public let ipv4: IPv4
    public var ip: any IP { ipv4 }
    public let maskV4: IPv4
    public var mask: any IP { maskV4 }
    public let maskInt: Int
    public let networkV4: NetworkV4
    public var network: any Network { networkV4 }

    public init?(from: String) {
        var from = from
        if !from.contains("/") {
            from = from + "/32"
        }
        let split = from.split(separator: "/")
        if split.count != 2 {
            return nil
        }
        let maskInt = Int(split[1])
        guard let maskInt else {
            return nil
        }
        let maskV4 = parseMask(maskInt, isv4: true)
        guard let maskV4 else {
            return nil
        }
        let v4 = IPv4(from: String(split[0]))
        guard let v4 else {
            return nil
        }
        ipv4 = v4
        self.maskV4 = IPv4(raw: maskV4)
        self.maskInt = maskInt
        var networkIp = (v4.bytes.0 & self.maskV4.bytes.0, v4.bytes.1 & self.maskV4.bytes.1,
                         v4.bytes.2 & self.maskV4.bytes.2, v4.bytes.3 & self.maskV4.bytes.3)
        networkV4 = NetworkV4(ipv4: IPv4(raw: &networkIp), maskInt: maskInt)!
    }
}

public struct CIDRv6: CIDR {
    public let ipv6: IPv6
    public var ip: any IP { ipv6 }
    public let maskV6: IPv6
    public var mask: any IP { maskV6 }
    public let maskInt: Int
    public let networkV6: NetworkV6
    public var network: any Network { networkV6 }

    public init?(from: String) {
        var from = from
        if !from.contains("/") {
            from = from + "/128"
        }
        let split = from.split(separator: "/")
        if split.count != 2 {
            return nil
        }
        let maskInt = Int(split[1])
        guard let maskInt else {
            return nil
        }
        let maskV6 = parseMask(maskInt, isv4: false)
        guard let maskV6 else {
            return nil
        }
        let v6 = IPv6(from: String(split[0]))
        guard let v6 else {
            return nil
        }
        ipv6 = v6
        self.maskV6 = IPv6(raw: maskV6)
        self.maskInt = maskInt
        var networkIp = (v6.bytes.0 & self.maskV6.bytes.0, v6.bytes.1 & self.maskV6.bytes.1,
                         v6.bytes.2 & self.maskV6.bytes.2, v6.bytes.3 & self.maskV6.bytes.3,
                         v6.bytes.4 & self.maskV6.bytes.4, v6.bytes.5 & self.maskV6.bytes.5,
                         v6.bytes.6 & self.maskV6.bytes.6, v6.bytes.7 & self.maskV6.bytes.7,
                         v6.bytes.8 & self.maskV6.bytes.8, v6.bytes.9 & self.maskV6.bytes.9,
                         v6.bytes.10 & self.maskV6.bytes.10, v6.bytes.11 & self.maskV6.bytes.11,
                         v6.bytes.12 & self.maskV6.bytes.12, v6.bytes.13 & self.maskV6.bytes.13,
                         v6.bytes.14 & self.maskV6.bytes.14, v6.bytes.15 & self.maskV6.bytes.15)
        networkV6 = NetworkV6(ipv6: IPv6(raw: &networkIp), maskInt: maskInt)!
    }
}
