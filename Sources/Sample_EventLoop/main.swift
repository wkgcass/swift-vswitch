#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import ArgumentParser
import SwiftEventLoopCommon
import SwiftEventLoopPosix
import VProxyCommon

struct EventLoopSample: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Proxy tcp traffic from <bind> to <target>.")

    @Option(help: "The port number to bind.") var bind: UInt16
    @Option(help: "The target ip:port to connect to.") var target: String

    func validate() throws {
        if GetIPPort(from: target) == nil {
            throw ValidationError("\(target) is not a valid ip:port")
        }
    }

    func run() {
        PosixFDs.setup()

        do {
            let v6: (any TcpFD)?
            do {
                v6 = try FDProvider.get().openIPv6Tcp()
            } catch { // may not support v6
                print("bind v6 failed, your system probably doesn't support ipv6?")
                v6 = nil
            }
            var v4: (any TcpFD)? = try FDProvider.get().openIPv4Tcp()

            try v6?.setOption(SockOpts.SO_REUSEADDR, true)
            try v4!.setOption(SockOpts.SO_REUSEADDR, true)

            try v6?.bind(GetIPPort(from: "[::]:\(bind)")!)
            do {
                try v4!.bind(GetIPPort(from: "0.0.0.0:\(bind)")!)
            } catch {
                // linux v6 [::]:{port} might also bind to v4 address
                v4 = nil
            }

            let loop = try SelectorEventLoop.open()
            let thread = FDProvider.get().newThread { loop.loop() }
            thread.start()

            let target = GetIPPort(from: target)!
            if let v4 {
                try loop.add(v4, ops: EventSet.read(), attachment: nil, AcceptHandler(target))
            }
            if let v6 {
                try loop.add(v6, ops: EventSet.read(), attachment: nil, AcceptHandler(target))
            }

            thread.join()
        } catch {
            print(error)
            return
        }
    }
}

class AcceptHandler: TcpHandler {
    private let target: IPPort
    init(_ target: IPPort) {
        self.target = target
    }

    public func readable(_ ctx: borrowing HandlerContext) throws {
        while true {
            guard let accepted = try fd(ctx).accept() else {
                return
            }
            let targetFD = if target is IPv4Port {
                try FDProvider.get().openIPv4Tcp()
            } else {
                try FDProvider.get().openIPv6Tcp()
            }
            try targetFD.connect(target)
            let session = Session(active: accepted, passive: targetFD)
            try ctx.eventLoop.add(accepted, ops: EventSet.read(), attachment: session, ProxyHandler(notConnected: false))
            try ctx.eventLoop.add(targetFD, ops: EventSet.write(), attachment: session, ProxyHandler(notConnected: true))
        }
    }

    public func writable(_: borrowing HandlerContext) throws {
        // will never fire
    }

    public func removed(_ ctx: borrowing HandlerContext) throws {
        ctx.fd.close()
    }
}

class Session {
    let active: any StreamFD
    let passive: any StreamFD

    let readBuf = RingBuffer<UInt8>(capacity: 16384)
    let sendBuf = RingBuffer<UInt8>(capacity: 16384)

    init(active: any StreamFD, passive: any StreamFD) {
        self.active = active
        self.passive = passive
    }

    func readBuf(of fd: any FD) -> RingBuffer<UInt8> {
        if active.handle() == fd.handle() {
            return readBuf
        } else {
            return sendBuf
        }
    }

    func sendBuf(of fd: any FD) -> RingBuffer<UInt8> {
        if active.handle() == fd.handle() {
            return sendBuf
        } else {
            return readBuf
        }
    }

    func another(from fd: any FD) -> any StreamFD {
        if active.handle() == fd.handle() {
            return passive
        } else {
            return active
        }
    }
}

class ProxyHandler: TcpHandler {
    private var notConnected: Bool
    init(notConnected: Bool) {
        self.notConnected = notConnected
    }

    public func readable(_ ctx: borrowing HandlerContext) throws {
        let sess = ctx.attachment as! Session
        let buf = sess.readBuf(of: ctx.fd)
        let n: Int
        do {
            n = try buf.storeFrom(fd(ctx).read)
        } catch {
            ctx.remove()
            return
        }
        if n < 0 {
            // EOF
            ctx.remove()
            return
        }
        if buf.freeSpace() == 0 {
            ctx.rmOps(EventSet.read())
        }
        ctx.eventLoop.addOps(sess.another(from: ctx.fd), ops: EventSet.write())
    }

    public func writable(_ ctx: borrowing HandlerContext) throws {
        if notConnected {
            do { try fd(ctx).finishConnect() } catch {
                ctx.remove()
                return
            }
            notConnected = false
            ctx.addOps(EventSet.read())
        }
        let sess = ctx.attachment as! Session
        let buf = sess.sendBuf(of: ctx.fd)
        do {
            _ = try buf.writeTo(fd(ctx).write)
        } catch {
            ctx.remove()
            return
        }
        if buf.usedSpace() == 0 {
            ctx.rmOps(EventSet.write())
        }
        ctx.eventLoop.addOps(sess.another(from: ctx.fd), ops: EventSet.read())
    }

    public func removed(_ ctx: borrowing HandlerContext) throws {
        let sess = ctx.attachment as! Session
        let another = sess.another(from: ctx.fd)
        if another.isOpen() {
            another.shutdownOutput()
        }
        ctx.fd.close()
    }
}

EventLoopSample.main()
