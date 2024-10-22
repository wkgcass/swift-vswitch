#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public protocol IP: CustomStringConvertible {
    var bytes: [UInt8] { get }
}

public func GetIP(from ip: String) -> IP? {
    let v4 = IPv4(ip)
    if v4 != nil {
        return v4
    }
    let v6 = IPv6(ip)
    if v6 != nil {
        return v6
    }
    return nil
}

public func GetIP(from bytes: [UInt8]) -> IP? {
    if bytes.capacity == 4 {
        return IPv4(bytes)
    } else if bytes.capacity == 16 {
        return IPv6(bytes)
    } else {
        return nil
    }
}

public struct IPv4: IP {
    private let bytes_: [UInt8]
    public var bytes: [UInt8] {
        return bytes_
    }

    public init?(_ ip: String) {
        bytes_ = Arrays.newArray(capacity: 4)
        let err = inet_pton(AF_INET, ip, Arrays.getRaw(from: bytes_))
        if err == 0 {
            return nil
        }
    }

    init(_ bytes: [UInt8]) {
        bytes_ = bytes
    }

    public var description: String {
        // 255.255.255.255\0
        let str: [CChar] = Arrays.newArray(capacity: 16)
        inet_ntop(AF_INET, bytes_, Arrays.getRaw(from: str), 16)
        // should always succeed
        return String(cString: Arrays.getRaw(from: str))
    }
}

public struct IPv6: IP {
    private let bytes_: [UInt8]
    public var bytes: [UInt8] {
        return bytes_
    }

    public init?(_ ip_: String) {
        var ip = ip_
        let l = ip.firstIndex(of: "[")
        if l != nil {
            let r = ip[l!...].lastIndex(of: "]")
            if r == nil { // has left bracket but no right bracket
                return nil
            }
            ip = String(ip[ip.index(l!, offsetBy: 1) ..< r!])
        }

        bytes_ = Arrays.newArray(capacity: 16)
        let err = inet_pton(AF_INET6, ip, Arrays.getRaw(from: bytes))
        if err == 0 {
            return nil
        }
    }

    init(_ bytes: [UInt8]) {
        bytes_ = bytes
    }

    public var description: String {
        // 1234:6789:1234:6789:1234:6789:1234:6789\0
        let str: [CChar] = Arrays.newArray(capacity: 40)
        inet_ntop(AF_INET6, bytes_, Arrays.getRaw(from: str), 40)
        // should always succeed
        return String(cString: Arrays.getRaw(from: str))
    }
}
