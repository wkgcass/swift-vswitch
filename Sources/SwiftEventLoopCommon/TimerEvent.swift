public class TimerEvent {
    private var event: (any TimeElem)?
    private let eventLoop: SelectorEventLoop
    private var canceled = false

    public init(_ eventLoop: SelectorEventLoop) {
        self.eventLoop = eventLoop
    }

    public func setEvent(_ event: any TimeElem) {
        if canceled {
            event.removeSelf() // this is invoked on event loop, so it's safe
            return
        }
        self.event = event
    }

    public func cancel() {
        if canceled {
            return
        }
        canceled = true
        if event == nil {
            return
        }
        eventLoop.nextTick(Runnable { self.event!.removeSelf() })
    }
}
