public protocol Network: CustomStringConvertible, Equatable, Hashable {
    var ip: any IP { get }
    var mask: any IP { get }
    var maskInt: Int { get }

    func contains(_ ip: (any IP)?) -> Bool
}

public extension Network {
    var description: String {
        return "\(ip)/\(maskInt)"
    }
}

public struct NetworkV4: Network {
    public let ipv4: IPv4
    public var ip: any IP { ipv4 }
    public let maskV4: IPv4
    public var mask: any IP { maskV4 }
    public let maskInt: Int

    public init?(from: String) {
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
    }

    public func contains(_ ip: (any IP)?) -> Bool {
        guard let v4 = ip as? IPv4 else {
            return false
        }
        return ipv4.bytes.0 == (maskV4.bytes.0 & v4.bytes.0) &&
            ipv4.bytes.1 == (maskV4.bytes.1 & v4.bytes.1) &&
            ipv4.bytes.2 == (maskV4.bytes.2 & v4.bytes.2) &&
            ipv4.bytes.3 == (maskV4.bytes.3 & v4.bytes.3)
    }
}

public struct NetworkV6: Network {
    public let ipv6: IPv6
    public var ip: any IP { ipv6 }
    public let maskV6: IPv6
    public var mask: any IP { maskV6 }
    public let maskInt: Int

    public init?(from: String) {
        let split = from.split(separator: "/")
        if split.count != 2 {
            return nil
        }
        let maskInt = Int(split[1])
        guard let maskInt else {
            return nil
        }
        let maskV6 = parseMask(maskInt, isv4: true)
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
    }

    public func contains(_ ip: (any IP)?) -> Bool {
        print("!!!! \(self) contains \(String(describing: ip))")
        guard let v6 = ip as? IPv6 else {
            return false
        }
        return ipv6.bytes.0 == (maskV6.bytes.0 & v6.bytes.0) &&
            ipv6.bytes.1 == (maskV6.bytes.1 & v6.bytes.1) &&
            ipv6.bytes.2 == (maskV6.bytes.2 & v6.bytes.2) &&
            ipv6.bytes.3 == (maskV6.bytes.3 & v6.bytes.3) &&
            ipv6.bytes.4 == (maskV6.bytes.4 & v6.bytes.4) &&
            ipv6.bytes.5 == (maskV6.bytes.5 & v6.bytes.5) &&
            ipv6.bytes.6 == (maskV6.bytes.6 & v6.bytes.6) &&
            ipv6.bytes.7 == (maskV6.bytes.7 & v6.bytes.7) &&
            ipv6.bytes.8 == (maskV6.bytes.8 & v6.bytes.8) &&
            ipv6.bytes.9 == (maskV6.bytes.9 & v6.bytes.9) &&
            ipv6.bytes.10 == (maskV6.bytes.10 & v6.bytes.10) &&
            ipv6.bytes.11 == (maskV6.bytes.11 & v6.bytes.11) &&
            ipv6.bytes.12 == (maskV6.bytes.12 & v6.bytes.12) &&
            ipv6.bytes.13 == (maskV6.bytes.13 & v6.bytes.13) &&
            ipv6.bytes.14 == (maskV6.bytes.14 & v6.bytes.14) &&
            ipv6.bytes.15 == (maskV6.bytes.15 & v6.bytes.15)
    }
}

func parseMask(_ mask: Int, isv4: Bool) -> [UInt8]? {
    if mask > 128 { // mask should not be greater than 128
        return nil
    }
    if mask > 32, isv4 {
        return nil
    }
    var result: [UInt8]
    if isv4 {
        // ipv4
        result = Arrays.newArray(capacity: 4)
        getMask(&result, mask: mask)
    } else {
        // ipv6
        result = Arrays.newArray(capacity: 16)
        getMask(&result, mask: mask)
    }
    return result
}

// fill bytes into the `masks` array
func getMask(_ masks: inout [UInt8], mask: Int) {
    var remainingMask = mask

    // because Swift initializes the array with 0
    // we only need to set 1 into the bit sequence
    // start from the first bit
    for i in 0 ..< masks.count {
        masks[i] = genPrefixByte(remainingMask)
        // the `to-do` bit sequence moves 8 bits forward each round
        // so subtract 8 from the integer represented mask
        remainingMask -= 8
    }
}

func genPrefixByte(_ mask: Int) -> UInt8 {
    let m = min(max(mask, 0), 8)
    return UInt8((0xFF << (8 - m)) & 0xFF)
}
