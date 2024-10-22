#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public func GetIPPort(from: String) -> IPPort? {
    let optindex = from.lastIndex(of: ":")
    if optindex == nil {
        return nil
    }
    let index = optindex!

    let ipPart = String(from[..<index])
    let portPart = String(from[from.index(index, offsetBy: 1)...])

    let ip = GetIP(from: ipPart)
    if ip == nil {
        return nil
    }
    let port = UInt16(portPart)
    if port == nil {
        return nil
    }
    if let v4 = ip as? IPv4 {
        return IPv4Port(v4, port!)
    } else {
        return IPv6Port(ip as! IPv6, port!)
    }
}

public protocol IPPort: CustomStringConvertible {
    var ip: IP { get }
    var port: UInt16 { get }
}

public extension IPPort {
    var description: String {
        if ip is IPv6 {
            return "[\(ip)]:\(port)"
        } else {
            return "\(ip):\(port)"
        }
    }

    func toGeneralSockAddr() -> (socklen_t, sockaddr_in6) {
        var ret = sockaddr_in6()
        if ip is IPv6 {
            ret.sin6_family = sa_family_t(AF_INET6)
        } else {
            ret.sin6_family = sa_family_t(AF_INET)
        }
        let port = Convert.reverseByteOrder(port)
        ret.sin6_port = port
        memcpy(&ret.sin6_addr, ip.bytes, ip.bytes.capacity)
        if ip is IPv6 {
            return (socklen_t(MemoryLayout<sockaddr_in6>.size), ret)
        } else {
            return (socklen_t(MemoryLayout<sockaddr_in>.size), ret)
        }
    }
}

public struct IPv4Port: IPPort {
    private let ip_: IPv4
    private let port_: UInt16
    public init(_ ip_: IPv4, _ port_: UInt16) {
        self.ip_ = ip_
        self.port_ = port_
    }

    public init(_ addr: sockaddr_in) {
        var xaddr = addr
        var bytes: [UInt8] = Arrays.newArray(capacity: 4)
        memcpy(&bytes, &xaddr.sin_addr.s_addr, 4)
        self.init(IPv4(bytes), Convert.reverseByteOrder(xaddr.sin_port))
    }

    public var ip: IP {
        return ip_
    }

    public var port: UInt16 {
        return port_
    }

    public func toSockAddr() -> sockaddr_in {
        var ret = sockaddr_in()
        ret.sin_family = sa_family_t(AF_INET)
        let port = Convert.reverseByteOrder(port_)
        ret.sin_port = port
        memcpy(&ret.sin_addr, ip_.bytes, 4)
        return ret
    }
}

public struct IPv6Port: IPPort {
    private let ip_: IPv6
    private let port_: UInt16
    public init(_ ip_: IPv6, _ port_: UInt16) {
        self.ip_ = ip_
        self.port_ = port_
    }

    public init(_ addr: sockaddr_in6) {
        var xaddr = addr
        var bytes: [UInt8] = Arrays.newArray(capacity: 16)
        memcpy(&bytes, &xaddr.sin6_addr, 16)
        self.init(IPv6(bytes), Convert.reverseByteOrder(xaddr.sin6_port))
    }

    public var ip: IP {
        return ip_
    }

    public var port: UInt16 {
        return port_
    }

    public func toSockAddr() -> sockaddr_in6 {
        var ret = sockaddr_in6()
        ret.sin6_family = sa_family_t(AF_INET6)
        let port = Convert.reverseByteOrder(port_)
        ret.sin6_port = port
        memcpy(&ret.sin6_addr, ip_.bytes, 16)
        return ret
    }
}
