import SwiftEventLoopCommon

public class NetStack {
    private let loop: SelectorEventLoop
    private let params: VSwitchParams

    init(loop: SelectorEventLoop, params: VSwitchParams) {
        self.loop = loop
        self.params = params
    }

    public func devrx(_: PacketBuffer) {
        // TODO: todo
    }

    public func iprx(_: PacketBuffer) {
        // TODO: todo
    }

    public func release() {
        // TODO: todo
    }
}
