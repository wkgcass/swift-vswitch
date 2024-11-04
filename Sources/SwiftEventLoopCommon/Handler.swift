public protocol Handler {
    func readable(_ ctx: borrowing HandlerContext) throws
    func writable(_ ctx: borrowing HandlerContext) throws
    // the SelectionKey is removed, or event loop is closed
    func removed(_ ctx: borrowing HandlerContext) throws
}

public protocol TcpHandler: Handler {}

public extension TcpHandler {
    func fd(_ ctx: borrowing HandlerContext) -> any TcpFD {
        return ctx.fd as! any TcpFD
    }
}

public protocol UdpHandler: Handler {}

public extension UdpHandler {
    func fd(_ ctx: borrowing HandlerContext) -> any UdpFD {
        return ctx.fd as! any UdpFD
    }
}

public struct HandlerContext: ~Copyable {
    public let eventLoop: SelectorEventLoop
    public let fd: any FD
    public let attachment: Any?

    init(eventLoop: SelectorEventLoop, fd: any FD, attachment: Any?) {
        self.eventLoop = eventLoop
        self.fd = fd
        self.attachment = attachment
    }

    public func remove() {
        eventLoop.remove(fd)
    }

    public func modify(_ ops: EventSet) {
        eventLoop.modify(fd, ops: ops)
    }

    public func addOps(_ ops: EventSet) {
        eventLoop.addOps(fd, ops: ops)
    }

    public func rmOps(_ ops: EventSet) {
        eventLoop.rmOps(fd, ops: ops)
    }

    public var ops: EventSet {
        return eventLoop.getOps(fd)
    }
}

public class DoNothingHandler: Handler {
    public init() {}
    public func readable(_: borrowing HandlerContext) throws {}
    public func writable(_: borrowing HandlerContext) throws {}
    public func removed(_: borrowing HandlerContext) throws {}
}
