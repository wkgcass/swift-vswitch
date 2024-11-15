#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public func GetIPPort(from: String) -> (any IPPort)? {
    let index = from.lastIndex(of: ":")
    guard let index else {
        return nil
    }

    let ipPart = String(from[..<index])
    let portPart = String(from[from.index(index, offsetBy: 1)...])

    let ip = GetIP(from: ipPart)
    if ip == nil {
        return nil
    }
    let port = UInt16(portPart)
    guard let port else {
        return nil
    }
    if let v4 = ip as? IPv4 {
        return IPv4Port(v4, port)
    } else {
        return IPv6Port(ip as! IPv6, port)
    }
}

public protocol IPPort: CustomStringConvertible, Hashable {
    var ip: any IP { get }
    var port: UInt16 { get }
    func equals(_ other: any IPPort) -> Bool
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
        let port = Utils.byteOrderConvert(port)
        ret.sin6_port = port
        ip.copyInto(&ret.sin6_addr)
        if ip is IPv6 {
            return (socklen_t(MemoryLayout<sockaddr_in6>.stride), ret)
        } else {
            return (socklen_t(MemoryLayout<sockaddr_in>.stride), ret)
        }
    }

    func equals(_ other: any IPPort) -> Bool {
        if let v4 = self as? IPv4Port {
            guard let other4 = other as? IPv4Port else {
                return false
            }
            return v4 == other4
        } else {
            let v6 = self as! IPv6Port
            guard let other6 = other as? IPv6Port else {
                return false
            }
            return v6 == other6
        }
    }
}

public struct IPv4Port: IPPort {
    private let ip_: IPv4
    public var ip: any IP { ip_ }
    public let port: UInt16
    public init(_ ip: IPv4, _ port: UInt16) {
        ip_ = ip
        self.port = port
    }

    public init(_ addr: sockaddr_in) {
        var xaddr = addr
        var bytes: [UInt8] = Arrays.newArray(capacity: 4, uninitialized: true)
        memcpy(&bytes, &xaddr.sin_addr.s_addr, 4)
        self.init(IPv4(raw: bytes), Utils.byteOrderConvert(xaddr.sin_port))
    }

    public func toSockAddr() -> sockaddr_in {
        var ret = sockaddr_in()
        ret.sin_family = sa_family_t(AF_INET)
        let port = Utils.byteOrderConvert(port)
        ret.sin_port = port
        ip_.copyInto(&ret.sin_addr)
        return ret
    }
}

public struct IPv6Port: IPPort {
    private let ip_: IPv6
    public var ip: any IP { ip_ }
    public let port: UInt16
    public init(_ ip: IPv6, _ port: UInt16) {
        ip_ = ip
        self.port = port
    }

    public init(_ addr: sockaddr_in6) {
        var xaddr = addr
        var bytes: [UInt8] = Arrays.newArray(capacity: 16, uninitialized: true)
        memcpy(&bytes, &xaddr.sin6_addr, 16)
        self.init(IPv6(raw: bytes), Utils.byteOrderConvert(xaddr.sin6_port))
    }

    public func toSockAddr() -> sockaddr_in6 {
        var ret = sockaddr_in6()
        ret.sin6_family = sa_family_t(AF_INET6)
        let port = Utils.byteOrderConvert(port)
        ret.sin6_port = port
        ip_.copyInto(&ret.sin6_addr)
        return ret
    }
}
