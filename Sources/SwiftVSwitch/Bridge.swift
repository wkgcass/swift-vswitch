import SwiftEventLoopCommon

public class Bridge {
    public let id: UInt32
    public let macTable: MacTable

    init(id: UInt32, loop: SelectorEventLoop, params: VSwitchParams) {
        self.id = id
        macTable = MacTable(loop: loop, params: params)
    }

    public func remove(iface: IfaceEx) {
        macTable.remove(iface: iface)
    }

    public func release() {
        macTable.release()
    }
}
