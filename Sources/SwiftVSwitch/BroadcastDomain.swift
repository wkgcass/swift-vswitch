import SwiftEventLoopCommon

public class BroadcastDomain {
    let macTable: MacTable

    init(loop: SelectorEventLoop, params: VSwitchParams) {
        macTable = MacTable(loop: loop, params: params)
    }

    public func remove(iface: any Iface) {
        macTable.remove(iface: iface)
    }

    public func release() {
        macTable.release()
    }
}
