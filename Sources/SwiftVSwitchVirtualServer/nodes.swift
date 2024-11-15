import SwiftVSwitch
import SwiftVSwitchCHelper
import SwiftVSwitchVirtualServerBase
import VProxyCommon

public func addIPVSNodes(_ mgr: NodeManager) {
    mgr.addNode(IPVSConnCreate())
}

class IPVSConnCreate: Node {
    private var natInput = NodeRef("nat-input")

    init() {
        super.init(name: "ipvs-conn-create")
    }

    override func initGraph(mgr: NodeManager) {
        super.initGraph(mgr: mgr)
        mgr.initRef(&natInput)
    }

    override func schedule(_ pkb: PacketBuffer, _ sched: inout Scheduler) {
        if !canCreateConn(pkb) {
            assert(Logger.lowLevelDebug("unable to create connection for \(pkb)"))
            return sched.schedule(pkb, to: drop)
        }
        let tup = pkb.tuple!
        let svcTup = PktTuple(proto: tup.proto,
                              srcPort: 0,
                              dstPort: tup.dstPort,
                              srcIp: tup.srcIp is IPv4 ? IPv4.ANY : IPv6.ANY,
                              dstIp: tup.dstIp)

        let svc = pkb.netstack!.ipvs.services[svcTup]
        guard let svc else {
            assert(Logger.lowLevelDebug("unable to find ipvs service for \(pkb)"))
            return sched.schedule(pkb, to: drop)
        }
        let dest = svc.schedule()
        guard let dest else {
            assert(Logger.lowLevelDebug("unable to find ipvs dest for \(pkb)"))
            return sched.schedule(pkb, to: drop)
        }

        let conntrack = pkb.netstack!.conntrack
        if dest.fwd == FwdMethod.FNAT {
            let afterNat = svc.findFreeLocalIPPort(dest, ct: conntrack)
            guard let afterNat else {
                return sched.schedule(pkb, to: drop)
            }

            let clientConn = Connection(ct: conntrack, isBeforeNat: true, tup: pkb.tuple!, nextNode: natInput)
            clientConn.dest = dest
            clientConn.fastOutput.enabled = true
            clientConn.fastOutput.enabled = true

            let serverConn = Connection(ct: conntrack, isBeforeNat: false, tup: afterNat, nextNode: natInput)
            serverConn.dest = dest
            serverConn.fastOutput.enabled = true
            serverConn.fastOutput.enabled = true

            clientConn.peer = serverConn
            serverConn.peer = clientConn

            conntrack.put(clientConn.tup, clientConn)
            conntrack.put(serverConn.tup, serverConn)
            clientConn.resetTimer()

            pkb.conn = clientConn
            return sched.schedule(pkb, to: natInput)
        } else {
            // TODO: other fwd methods
            assert(Logger.lowLevelDebug("unsupported fwd method: \(dest.fwd)"))
            return sched.schedule(pkb, to: drop)
        }
    }

    private func canCreateConn(_ pkb: PacketBuffer) -> Bool {
        if pkb.proto == IP_PROTOCOL_TCP {
            let tcp: UnsafeMutablePointer<swvs_tcphdr> = Convert.ptr2mutUnsafe(pkb.upper!)
            if tcp.pointee.flags != TCP_FLAGS_SYN {
                // only syn can establish a new connection
                return false
            }
        }
        return true
    }
}
