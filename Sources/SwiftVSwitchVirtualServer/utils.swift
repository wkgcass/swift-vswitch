import VProxyCommon
import SwiftVSwitch
import SwiftVSwitchVirtualServerBase

public extension Service {
    func findFreeLocalIPPort(_ dest: Dest, ct: Conntrack) -> PktTuple? {
        if dest.ip is IPv4 {
            return localipv4.findFreeIPPort(dest, proto: proto, ct: ct)
        } else {
            return localipv6.findFreeIPPort(dest, proto: proto, ct: ct)
        }
    }
}

public extension IPPool {
    func findFreeIPPort(_ dest: Dest, proto: UInt8, ct: Conntrack) -> PktTuple? {
        let ipList = self.ips
        if ipList.count == 0 {
            assert(Logger.lowLevelDebug("no localip available"))
            return nil
        }
        if offset >= ipList.count {
            offset = offset % ipList.count
        }
        for _ in 0 ..< 10 {
            let ip = ipList[offset]
            offset += 1
            if offset >= ipList.count {
                offset = 0
            }

            for _ in 0 ..< 20 {
                var port = UInt16.random(in: 1 ... 65535)
                port = port & portMask

                assert(Logger.lowLevelDebug("trying ip=\(ip) port=\(port)"))

                let tup = PktTuple(proto: proto, srcPort: dest.port, dstPort: port,
                                   srcIp: dest.ip, dstIp: ip)
                let conn = ct.lookup(tup)
                if conn == nil {
                    // we can use the ip + rand-port
                    return tup
                }
            }
        }
        assert(Logger.lowLevelDebug("unable to find free ip:port with many retries"))
        return nil
    }
}
