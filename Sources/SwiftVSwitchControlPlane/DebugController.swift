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
#if SWVS_DEBUG
        api.get("connections", use: debugConnections)
#endif
    }

#if SWVS_DEBUG
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
}
