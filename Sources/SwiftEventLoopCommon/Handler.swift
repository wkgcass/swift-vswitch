public protocol Handler {
    func readable(_ ctx: HandlerContext) throws
    func writable(_ ctx: HandlerContext) throws
    // the SelectionKey is removed, or event loop is closed
    func removed(_ ctx: HandlerContext) throws
}

public protocol TcpHandler: Handler {}

public extension TcpHandler {
    func fd(_ ctx: HandlerContext) -> any TcpFD {
        return ctx.fd as! any TcpFD
    }
}

public protocol UdpHandler: Handler {}

public extension UdpHandler {
    func fd(_ ctx: HandlerContext) -> any UdpFD {
        return ctx.fd as! any UdpFD
    }
}

public struct HandlerContext {
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
