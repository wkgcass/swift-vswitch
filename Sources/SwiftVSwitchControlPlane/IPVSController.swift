import SwiftVSwitch
import SwiftVSwitchControlData
import Vapor
import VProxyCommon

struct IPVSController: RouteCollection, @unchecked Sendable {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    func boot(routes: any Vapor.RoutesBuilder) throws {
        let api = routes.grouped("apis", "v1.0", "netstacks", ":ns", "ipvs")
        api.get("services", use: listServices)
        api.post("services", "query", use: filterServices)
        api.get("connections", use: listConnections)
        api.post("connections", "query", use: filterConnections)
    }

    private func listServices(req: Request) async throws -> [ServiceRef] {
        let nsStr = req.parameters.get("ns")!
        let ns = UInt32(nsStr)
        guard let ns else {
            throw Abort(.badRequest, reason: "netstack/:id expects an unsigned integer, but got \(nsStr)")
        }

        let box = try sw.queryWithErr { sw in
            guard let ns = sw.netstacks[ns] else {
                throw Abort(.notFound, reason: "netstack/\(ns) not found")
            }

            let services = Box([ServiceRef]())
            for svc in ns.ipvs.services.values {
                var ref = formatService(svc, keepStats: false)
                fillStats(ns.id, svc, &ref)
                services.pointee.append(ref)
            }
            return services
        }!
        return box.pointee
    }

    private func filterServices(req: Request) async throws -> [ServiceRef] {
        let nsStr = req.parameters.get("ns")!
        let ns = UInt32(nsStr)
        guard let ns else {
            throw Abort(.badRequest, reason: "netstack/:id expects an unsigned integer, but got \(nsStr)")
        }
        let filter = try req.content.decode(ServiceFilter.self)
        let filterIp = GetIP(from: filter.vip)
        guard let filterIp else {
            throw Abort(.badRequest, reason: "filter.vip is not a valid ip \(filter.vip)")
        }

        let box = try sw.queryWithErr { sw in
            guard let ns = sw.netstacks[ns] else {
                throw Abort(.notFound, reason: "netstack/\(ns) not found")
            }

            let services = Box([ServiceRef]())
            for svc in ns.ipvs.services.values {
                if svc.proto != filter.proto || !svc.vip.equals(filterIp) || svc.port != filter.port {
                    continue
                }
                var ref = formatService(svc, keepStats: false)
                fillStats(ns.id, svc, &ref)
                services.pointee.append(ref)
            }
            return services
        }!
        return box.pointee
    }

    private func formatService(_ svc: Service, keepStats: Bool) -> ServiceRef {
        var dests = [DestRef]()
        for dest in svc.dests {
            dests.append(formatDest(dest, keepStats: keepStats))
        }
        var ret = ServiceRef(
            proto: svc.proto,
            vip: svc.vip.description,
            port: svc.port,
            dests: dests,
            sched: svc.sched.fullname,
            localipv4: svc.localipv4.ips.map { ip in ip.description },
            localipv6: svc.localipv6.ips.map { ip in ip.description },
            statistics: ServiceStatistics()
        )
        if keepStats {
            ret.statistics.inc(svc.statistics)
        }
        return ret
    }

    private func formatDest(_ dest: Dest, keepStats: Bool) -> DestRef {
        var ref = DestRef(
            ip: dest.ip.description,
            port: dest.port,
            weight: dest.weight,
            fwd: String(describing: dest.fwd).lowercased(),
            statistics: DestStatistics()
        )
        if keepStats {
            ref.statistics.inc(dest.statistics)
        }
        return ref
    }

    private func fillStats(_ netstackId: UInt32, _ svc: Service, _ ref: inout ServiceRef) {
        let results = sw.queryEachWorker { sw -> Box<ServiceRef>? in
            guard let ns = sw.netstacks[netstackId] else {
                return nil
            }
            guard let svc = ns.ipvs.services[GetServiceTuple(proto: svc.proto, vip: svc.vip, port: svc.port)] else {
                return nil
            }
            let result = formatService(svc, keepStats: true)
            return Box(result)
        }
        for res in results {
            guard let res else {
                continue
            }
            ref.statistics.inc(res.pointee.statistics)
            for idx in ref.dests.indices {
                for dest in res.pointee.dests {
                    if dest.ip == ref.dests[idx].ip, dest.port == ref.dests[idx].port {
                        ref.dests[idx].statistics.inc(dest.statistics)
                        break
                    }
                }
            }
        }
    }

    private func listConnections(req: Request) async throws -> [ConnRef] {
        let nsStr = req.parameters.get("ns")!
        let ns = UInt32(nsStr)
        guard let ns else {
            throw Abort(.badRequest, reason: "netstack/:id expects an unsigned integer, but got \(nsStr)")
        }

        let results = sw.queryEachWorker { sw -> Box<[ConnRef]>? in
            guard let ns = sw.netstacks[ns] else {
                return nil
            }

            let conns = Box([ConnRef]())
            for svc in ns.ipvs.services.values {
                for n in svc.connList.seq() {
                    if !n.isBeforeNat {
                        continue
                    }
                    let ref = formatConnection(n, withPeer: true)
                    conns.pointee.append(ref)
                }
            }
            return conns
        }
        var join = [ConnRef]()
        for arr in results {
            guard let arr else {
                continue
            }
            for conn in arr.pointee {
                join.append(conn)
            }
        }
        return join
    }

    private func filterConnections(req: Request) async throws -> [ConnRef] {
        let nsStr = req.parameters.get("ns")!
        let ns = UInt32(nsStr)
        guard let ns else {
            throw Abort(.badRequest, reason: "netstack/:id expects an unsigned integer, but got \(nsStr)")
        }
        let filter = try req.content.decode(ServiceFilter.self)
        let filterIp = GetIP(from: filter.vip)
        guard let filterIp else {
            throw Abort(.badRequest, reason: "filter.vip is not a valid ip \(filter.vip)")
        }

        let results = sw.queryEachWorker { sw -> Box<[ConnRef]>? in
            guard let ns = sw.netstacks[ns] else {
                return nil
            }

            let conns = Box([ConnRef]())
            for svc in ns.ipvs.services.values {
                if svc.proto != filter.proto || !svc.vip.equals(filterIp) || svc.port != filter.port {
                    continue
                }

                for n in svc.connList.seq() {
                    if !n.isBeforeNat {
                        continue
                    }
                    let ref = formatConnection(n, withPeer: true)
                    conns.pointee.append(ref)
                }
            }
            return conns
        }
        var join = [ConnRef]()
        for arr in results {
            guard let arr else {
                continue
            }
            for conn in arr.pointee {
                join.append(conn)
            }
        }
        return join
    }
}
