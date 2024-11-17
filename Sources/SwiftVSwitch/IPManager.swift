import Collections
import VProxyCommon

public class IPManager {
    public private(set) var ipv4 = [IPv4: Set<IfaceEx>]()
    public private(set) var ipv6 = [IPv6: Set<IfaceEx>]()
    public private(set) var dev2ipv4 = [IfaceHandle: Set<IPMaskv4>]()
    public private(set) var dev2ipv6 = [IfaceHandle: Set<IPMaskv6>]()

    public func getBy(iface: IfaceEx) -> (Set<IPMaskv4>, Set<IPMaskv6>) {
        let v4 = dev2ipv4[iface.handle()] ?? Set()
        let v6 = dev2ipv6[iface.handle()] ?? Set()
        return (v4, v6)
    }

    public func addIp(_ ipmask: (any IPMask)?, dev: IfaceEx) {
        if let v4 = ipmask as? IPMaskv4 {
            if !ipv4.keys.contains(v4.ipv4) {
                ipv4[v4.ipv4] = Set()
            }
            ipv4[v4.ipv4]!.insert(dev)

            if !dev2ipv4.keys.contains(dev.iface.handle()) {
                dev2ipv4[dev.iface.handle()] = Set()
            }
            dev2ipv4[dev.iface.handle()]!.insert(v4)
        } else if let v6 = ipmask as? IPMaskv6 {
            if !ipv6.keys.contains(v6.ipv6) {
                ipv6[v6.ipv6] = Set()
            }
            ipv6[v6.ipv6]!.insert(dev)

            if !dev2ipv6.keys.contains(dev.iface.handle()) {
                dev2ipv6[dev.iface.handle()] = Set()
            }
            dev2ipv6[dev.iface.handle()]!.insert(v6)
        }
    }

    public func removeIp(_ ipmask: (any IPMask)?, dev: IfaceEx) {
        if let v4 = ipmask as? IPMaskv4 {
            if ipv4.keys.contains(v4.ipv4) {
                ipv4[v4.ipv4]!.remove(dev)
                if ipv4[v4.ipv4]!.isEmpty {
                    ipv4.removeValue(forKey: v4.ipv4)
                }
            }
            if dev2ipv4.keys.contains(dev.handle()) {
                dev2ipv4[dev.handle()]!.remove(v4)
                if dev2ipv4[dev.handle()]!.isEmpty {
                    dev2ipv4.removeValue(forKey: dev.handle())
                }
            }
        } else if let v6 = ipmask as? IPMaskv6 {
            if ipv6.keys.contains(v6.ipv6) {
                ipv6[v6.ipv6]!.remove(dev)
                if ipv6[v6.ipv6]!.isEmpty {
                    ipv6.removeValue(forKey: v6.ipv6)
                }
            }
            if dev2ipv6.keys.contains(dev.handle()) {
                dev2ipv6[dev.handle()]!.remove(v6)
                if dev2ipv6[dev.handle()]!.isEmpty {
                    dev2ipv6.removeValue(forKey: dev.handle())
                }
            }
        }
    }
}
