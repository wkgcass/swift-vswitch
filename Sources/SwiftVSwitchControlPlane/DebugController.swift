import SwiftVSwitch
import SwiftVSwitchControlData
import Vapor

struct DebugController: RouteCollection, @unchecked Sendable {
    private let sw: VSwitch
    public init(_ sw: VSwitch) {
        self.sw = sw
    }

    func boot(routes: any Vapor.RoutesBuilder) throws {
        let api = routes.grouped("apis", "v1.0", "debug")
#if GLOBAL_WEAK_CONN_DEBUG
        api.get("connections", use: debugConnections)
#endif
#if REDIRECT_TIME_COST_DEBUG
        api.get("redirect", "cost", use: debugRedirectCost)
#endif
    }

#if GLOBAL_WEAK_CONN_DEBUG
    private func debugConnections(req _: Request) async throws -> [ConnRef] {
        WeakConnRef.lock.lock()
        var results = [ConnRef]()
        for conn in WeakConnRef.refs {
            guard let conn = conn.conn else {
                continue
            }
            let connref = formatConnection(conn)
            results.append(connref)
        }
        WeakConnRef.lock.unlock()
        return results
    }
#endif

#if REDIRECT_TIME_COST_DEBUG
    private func debugRedirectCost(req _: Request) async throws -> RedirectCost {
        return RedirectCost(redirectCount: sw.redirectCount.load(ordering: .relaxed), redirectCostUSecs: sw.redirectCostUSecs.load(ordering: .relaxed))
    }
#endif
}
