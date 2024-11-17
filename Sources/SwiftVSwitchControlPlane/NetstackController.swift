import SwiftVSwitch
import SwiftVSwitchControlData
import Vapor
import VProxyCommon

struct NetstackController: RouteCollection, @unchecked Sendable {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    func boot(routes: any Vapor.RoutesBuilder) throws {
        let api = routes.grouped("apis", "v1.0", "netstacks")
        api.get(use: listNetstacks)
    }

    private func listNetstacks(req _: Request) async throws -> [NetstackRef] {
        let box = sw.query { sw in
            let netstacks = Box([NetstackRef]())
            for ns in sw.netstacks.values {
                netstacks.pointee.append(NetstackRef(
                    name: "ns\(ns.id)",
                    id: ns.id
                ))
            }
            return netstacks
        }!
        return box.pointee
    }
}

func formatConnection(_ conn: Connection, withPeer: Bool = true) -> ConnRef {
    let ref = ConnRef(
        cid: conn.ct.sw.index,
        proto: conn.tup.proto,
        src: conn.tup.srcIp.description,
        srcPort: conn.tup.srcPort,
        dst: conn.tup.dstIp.description,
        dstPort: conn.tup.dstPort,
        state: "\(conn.state)",
        timeoutMillis: conn.getTimeoutMillis(),
        ttl: conn.timer?.ttl ?? -1,
        isBeforeNat: conn.isBeforeNat,
        address: Int(bitPattern: Unmanaged<Connection>.passUnretained(conn).toOpaque()),
        peer: nil
    )
    if withPeer, let peer = conn.peer {
        ref.peer = formatConnection(peer, withPeer: false)
    }
    return ref
}
