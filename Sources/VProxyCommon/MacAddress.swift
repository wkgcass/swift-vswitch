import Foundation

public struct MacAddress: CustomStringConvertible, Equatable, Hashable {
    public let bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    public init(raw: UnsafeRawPointer) {
        let p: UnsafePointer<UInt8> = Convert.raw2ptr(raw)
        bytes = (p.pointee, p.advanced(by: 1).pointee, p.advanced(by: 2).pointee,
                 p.advanced(by: 3).pointee, p.advanced(by: 4).pointee, p.advanced(by: 5).pointee)
    }

    public init?(from s: String) {
        let split = s.components(separatedBy: ":")
        if split.count != 6 {
            return nil
        }
        let _0 = UInt8(split[0], radix: 16)
        let _1 = UInt8(split[1], radix: 16)
        let _2 = UInt8(split[2], radix: 16)
        let _3 = UInt8(split[3], radix: 16)
        let _4 = UInt8(split[4], radix: 16)
        let _5 = UInt8(split[5], radix: 16)

        guard let _0 else { return nil }
        guard let _1 else { return nil }
        guard let _2 else { return nil }
        guard let _3 else { return nil }
        guard let _4 else { return nil }
        guard let _5 else { return nil }

        bytes = (_0, _1, _2, _3, _4, _5)
    }

    public func copyInto(_ p: UnsafeMutableRawPointer) {
        let u: UnsafeMutablePointer<UInt8> = Convert.mutraw2mutptr(p)
        u.pointee = bytes.0
        u.advanced(by: 1).pointee = bytes.1
        u.advanced(by: 2).pointee = bytes.2
        u.advanced(by: 3).pointee = bytes.3
        u.advanced(by: 4).pointee = bytes.4
        u.advanced(by: 5).pointee = bytes.5
    }

    public func isBroadcast() -> Bool {
        return bytes.0 == 0xff &&
            bytes.1 == 0xff &&
            bytes.2 == 0xff &&
            bytes.3 == 0xff &&
            bytes.4 == 0xff &&
            bytes.5 == 0xff
    }

    public func isMulticast() -> Bool {
        return isIpv4Multicast() || isIpv6Multicast()
    }

    public func isUnicast() -> Bool {
        return !isBroadcast() && !isMulticast()
    }

    private func isIpv4Multicast() -> Bool {
        // 0000 0001 0000 0000 0101 1110 0.......
        if bytes.0 != 0b0000_0001 {
            return false
        }
        if bytes.1 != 0b0000_0000 {
            return false
        }
        if bytes.2 != 0b0101_1110 {
            return false
        }
        if (bytes.3 & 0b1000_0000) != 0b0000_0000 { // first bit 0
            return false
        }
        return true
    }

    private func isIpv6Multicast() -> Bool {
        return bytes.0 == 0x33 && bytes.1 == 0x33
    }

    public var description: String {
        return String(format: "%02x:%02x:%02x:%02x:%02x:%02x",
                      bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bytes.0)
        hasher.combine(bytes.1)
        hasher.combine(bytes.2)
        hasher.combine(bytes.3)
        hasher.combine(bytes.4)
        hasher.combine(bytes.5)
    }

    public static func == (lhs: MacAddress, rhs: MacAddress) -> Bool {
        return lhs.bytes == rhs.bytes
    }
}
