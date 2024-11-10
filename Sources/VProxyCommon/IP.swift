#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public protocol IP: CustomStringConvertible, Equatable, Hashable {
    func copyInto(_ p: UnsafeMutableRawPointer)
}

public extension IP {
    func equals(_ other: any IP) -> Bool {
        if let v4 = self as? IPv4 {
            guard let o = other as? IPv4 else {
                return false
            }
            return v4 == o
        } else {
            let v6 = self as! IPv6
            guard let o = other as? IPv6 else {
                return false
            }
            return v6 == o
        }
    }
}

public func GetAnyIpWithSameAFAs(ip: any IP) -> any IP {
    return ip is IPv4 ? IPv4.ANY : IPv6.ANY
}

public func GetIP(from ip: String) -> (any IP)? {
    let v4 = IPv4(from: ip)
    if v4 != nil {
        return v4
    }
    let v6 = IPv6(from: ip)
    if v6 != nil {
        return v6
    }
    return nil
}

public func GetIP(from bytes: [UInt8]) -> (any IP)? {
    if bytes.capacity == 4 {
        return IPv4(raw: bytes)
    } else if bytes.capacity == 16 {
        return IPv6(raw: bytes)
    } else {
        return nil
    }
}

public struct IPv4: IP {
    public let bytes: (UInt8, UInt8, UInt8, UInt8)

    public init?(from ip: String) {
        var tmp = in_addr()
        let err = inet_pton(AF_INET, ip, &tmp)
        if err == 0 {
            return nil
        }
        bytes = IPv4.format(&tmp)
    }

    private static func format(_ p: UnsafeRawPointer) -> (UInt8, UInt8, UInt8, UInt8) {
        let u8p: UnsafePointer<UInt8> = Convert.raw2ptr(p)
        return (u8p.pointee, u8p.advanced(by: 1).pointee, u8p.advanced(by: 2).pointee, u8p.advanced(by: 3).pointee)
    }

    public init(raw bytes: UnsafeRawPointer) {
        let u8p: UnsafePointer<UInt8> = Convert.raw2ptr(bytes)
        self.bytes = (u8p.pointee, u8p.advanced(by: 1).pointee,
                      u8p.advanced(by: 2).pointee, u8p.advanced(by: 3).pointee)
    }

    public func toUInt32() -> UInt32 {
        return (UInt32(bytes.0) << 24) | (UInt32(bytes.1) << 16) | (UInt32(bytes.2) << 8) | UInt32(bytes.3)
    }

    public func copyInto(_ p: UnsafeMutableRawPointer) {
        let u8p: UnsafeMutablePointer<UInt8> = Convert.mutraw2mutptr(p)
        u8p.pointee = bytes.0
        u8p.advanced(by: 1).pointee = bytes.1
        u8p.advanced(by: 2).pointee = bytes.2
        u8p.advanced(by: 3).pointee = bytes.3
    }

    public var description: String {
        return "\(bytes.0).\(bytes.1).\(bytes.2).\(bytes.3)"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bytes.0)
        hasher.combine(bytes.1)
        hasher.combine(bytes.2)
        hasher.combine(bytes.3)
    }

    public static func == (lhs: IPv4, rhs: IPv4) -> Bool {
        return lhs.bytes == rhs.bytes
    }

    public nonisolated(unsafe) static let ANY = IPv4(from: "0.0.0.0")!
}

public struct IPv6: IP {
    public let bytes: (UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8)

    public init?(from ip_: String) {
        var ip = ip_
        let l = ip.firstIndex(of: "[")
        if l != nil {
            let r = ip[l!...].lastIndex(of: "]")
            if r == nil { // has left bracket but no right bracket
                return nil
            }
            ip = String(ip[ip.index(l!, offsetBy: 1) ..< r!])
        }

        var tmp = in6_addr()
        let err = inet_pton(AF_INET6, ip, &tmp)
        if err == 0 {
            return nil
        }
        bytes = IPv6.format(&tmp)
    }

    public func isMulticast() -> Bool {
        return bytes.0 == 0xff
    }

    private static func format(_ p: UnsafeRawPointer) -> (UInt8, UInt8, UInt8, UInt8,
                                                          UInt8, UInt8, UInt8, UInt8,
                                                          UInt8, UInt8, UInt8, UInt8,
                                                          UInt8, UInt8, UInt8, UInt8)
    {
        let u8p: UnsafePointer<UInt8> = Convert.raw2ptr(p)
        return (u8p.pointee, u8p.advanced(by: 1).pointee, u8p.advanced(by: 2).pointee, u8p.advanced(by: 3).pointee,
                u8p.advanced(by: 4).pointee, u8p.advanced(by: 5).pointee, u8p.advanced(by: 6).pointee, u8p.advanced(by: 7).pointee,
                u8p.advanced(by: 8).pointee, u8p.advanced(by: 9).pointee, u8p.advanced(by: 10).pointee, u8p.advanced(by: 11).pointee,
                u8p.advanced(by: 12).pointee, u8p.advanced(by: 13).pointee, u8p.advanced(by: 14).pointee, u8p.advanced(by: 15).pointee)
    }

    public init(raw bytes: UnsafeRawPointer) {
        let u8p: UnsafePointer<UInt8> = Convert.raw2ptr(bytes)
        self.bytes = (
            u8p.pointee, u8p.advanced(by: 1).pointee, u8p.advanced(by: 2).pointee, u8p.advanced(by: 3).pointee,
            u8p.advanced(by: 4).pointee, u8p.advanced(by: 5).pointee, u8p.advanced(by: 6).pointee, u8p.advanced(by: 7).pointee,
            u8p.advanced(by: 8).pointee, u8p.advanced(by: 9).pointee, u8p.advanced(by: 10).pointee, u8p.advanced(by: 11).pointee,
            u8p.advanced(by: 12).pointee, u8p.advanced(by: 13).pointee, u8p.advanced(by: 14).pointee, u8p.advanced(by: 15).pointee
        )
    }

    public func toUInt128() -> (UInt64, UInt64) {
        let h = (UInt64(bytes.0) << 56) | (UInt64(bytes.1) << 48) | (UInt64(bytes.2) << 40) | (UInt64(bytes.3) << 32) |
            (UInt64(bytes.4) << 24) | (UInt64(bytes.5) << 16) | (UInt64(bytes.6) << 8) | UInt64(bytes.7)
        let l = (UInt64(bytes.8) << 56) | (UInt64(bytes.9) << 48) | (UInt64(bytes.10) << 40) | (UInt64(bytes.11) << 32) |
            (UInt64(bytes.12) << 24) | (UInt64(bytes.13) << 16) | (UInt64(bytes.14) << 8) | UInt64(bytes.15)
        return (l, h)
    }

    public func copyInto(_ p: UnsafeMutableRawPointer) {
        let u8p: UnsafeMutablePointer<UInt8> = Convert.mutraw2mutptr(p)
        u8p.pointee = bytes.0
        u8p.advanced(by: 1).pointee = bytes.1
        u8p.advanced(by: 2).pointee = bytes.2
        u8p.advanced(by: 3).pointee = bytes.3

        u8p.advanced(by: 4).pointee = bytes.4
        u8p.advanced(by: 5).pointee = bytes.5
        u8p.advanced(by: 6).pointee = bytes.6
        u8p.advanced(by: 7).pointee = bytes.7

        u8p.advanced(by: 8).pointee = bytes.8
        u8p.advanced(by: 9).pointee = bytes.9
        u8p.advanced(by: 10).pointee = bytes.10
        u8p.advanced(by: 11).pointee = bytes.11

        u8p.advanced(by: 12).pointee = bytes.12
        u8p.advanced(by: 13).pointee = bytes.13
        u8p.advanced(by: 14).pointee = bytes.14
        u8p.advanced(by: 15).pointee = bytes.15
    }

    public var description: String {
        // 1234:6789:1234:6789:1234:6789:1234:6789\0
        var str: [CChar] = Arrays.newArray(capacity: 40, uninitialized: true)
        var raw = in6_addr()
        copyInto(&raw)
        inet_ntop(AF_INET6, &raw, &str, 40)
        // should always succeed
        return String(cString: &str)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bytes.0)
        hasher.combine(bytes.1)
        hasher.combine(bytes.2)
        hasher.combine(bytes.3)
        hasher.combine(bytes.4)
        hasher.combine(bytes.5)
        hasher.combine(bytes.6)
        hasher.combine(bytes.7)
        hasher.combine(bytes.8)
        hasher.combine(bytes.9)
        hasher.combine(bytes.10)
        hasher.combine(bytes.11)
        hasher.combine(bytes.12)
        hasher.combine(bytes.13)
        hasher.combine(bytes.14)
        hasher.combine(bytes.15)
    }

    public static func == (lhs: IPv6, rhs: IPv6) -> Bool {
        return lhs.bytes.0 == rhs.bytes.0 &&
            lhs.bytes.1 == rhs.bytes.1 &&
            lhs.bytes.2 == rhs.bytes.2 &&
            lhs.bytes.3 == rhs.bytes.3 &&
            lhs.bytes.4 == rhs.bytes.4 &&
            lhs.bytes.5 == rhs.bytes.5 &&
            lhs.bytes.6 == rhs.bytes.6 &&
            lhs.bytes.7 == rhs.bytes.7 &&
            lhs.bytes.8 == rhs.bytes.8 &&
            lhs.bytes.9 == rhs.bytes.9 &&
            lhs.bytes.10 == rhs.bytes.10 &&
            lhs.bytes.11 == rhs.bytes.11 &&
            lhs.bytes.12 == rhs.bytes.12 &&
            lhs.bytes.13 == rhs.bytes.13 &&
            lhs.bytes.14 == rhs.bytes.14 &&
            lhs.bytes.15 == rhs.bytes.15
    }

    public nonisolated(unsafe) static let ANY = IPv6(from: "::")!
}
