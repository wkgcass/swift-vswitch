#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Collections
import poptrie
import VProxyCommon

public class RouteTable: CustomStringConvertible {
    public private(set) var rulesV4 = [NetworkV4: RouteRule]()
    public private(set) var rulesV6 = [NetworkV6: RouteRule]()
    private var pt = poptrie()

    public init?() {
        let ret = poptrie_init(&pt, 8, 12)
        if ret == nil {
            return nil
        }
    }

    public func lookup(ip: (any IP)?) -> RouteRule? {
        if let v4 = ip as? IPv4 {
            let raw = poptrie_lookup(&pt, v4.toUInt32())
            guard let raw else {
                return nil
            }
            return Unsafe.convertFromNativeKeepRef(raw)
        } else if let v6 = ip as? IPv6 {
            let ipx = uint128_s(n: v6.toUInt128())
            let raw = poptrie6_lookup_s(&pt, ipx)
            guard let raw else {
                return nil
            }
            return Unsafe.convertFromNativeKeepRef(raw)
        }
        return nil
    }

    public func addRule(_ r: RouteRule) {
        if let v4 = r.rule as? NetworkV4 {
            if rulesV4.keys.contains(v4) {
                poptrie_route_change(&pt, v4.ipv4.toUInt32(), Int32(r.rule.maskInt), Unmanaged.passUnretained(r).toOpaque())
            } else {
                poptrie_route_add(&pt, v4.ipv4.toUInt32(), Int32(r.rule.maskInt), Unmanaged.passUnretained(r).toOpaque())
            }
            rulesV4[v4] = r
        } else if let v6 = r.rule as? NetworkV6 {
            let ip = uint128_s(n: v6.ipv6.toUInt128())
            if rulesV6.keys.contains(v6) {
                poptrie6_route_change_s(&pt, ip, Int32(r.rule.maskInt), Unmanaged.passUnretained(r).toOpaque())
            } else {
                poptrie6_route_add_s(&pt, ip, Int32(r.rule.maskInt), Unmanaged.passUnretained(r).toOpaque())
            }
            rulesV6[v6] = r
        }
    }

    public func delRule(_ rule: any Network) {
        if let v4 = rule as? NetworkV4 {
            poptrie_route_del(&pt, v4.ipv4.toUInt32(), Int32(rule.maskInt))
            rulesV4.removeValue(forKey: v4)
        } else if let v6 = rule as? NetworkV6 {
            let ip = uint128_s(n: v6.ipv6.toUInt128())
            poptrie6_route_del_s(&pt, ip, Int32(rule.maskInt))
        }
    }

    public func release() {
        poptrie_release(&pt)
        rulesV4.removeAll()
        rulesV6.removeAll()
    }

    public var description: String {
        return "RouteTable{\(rulesV4) + \(rulesV6)}"
    }

    public class RouteRule: CustomStringConvertible {
        public let rule: any Network
        public let gateway: (any IP)?
        public let dev: IfaceEx
        public let src: any IP

        public init(rule: any Network, dev: IfaceEx, src: any IP) {
            self.rule = rule
            gateway = nil
            self.dev = dev
            self.src = src
        }

        public init(rule: any Network, via: any IP, dev: IfaceEx, src: any IP) {
            self.rule = rule
            gateway = via
            self.dev = dev
            self.src = src
        }

        public func isLocalDirect() -> Bool {
            return gateway == nil
        }

        public var description: String {
            if let gateway {
                return "\(rule) via \(gateway) dev \(dev.name) src \(src)"
            } else {
                return "\(rule) dev \(dev.name) src \(src)"
            }
        }
    }
}
