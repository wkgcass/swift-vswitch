#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import SwiftEventLoopCommon
import SwiftEventLoopPosix
import Testing
import VProxyCommon

struct TestSelectorEventLoop {
    init() {
        PosixFDs.setup()
    }

    @Test func testSelectorEventLoop() throws {
        let loop = try SelectorEventLoop.open()
        loop.loop { r in FDProvider.get().newThread(r) }
        var loopOnLoop: SelectorEventLoop?
        loop.runOnLoop {
            loopOnLoop = SelectorEventLoop.current()
        }
        while loopOnLoop == nil {
            OS.sleep(millis: 1)
        }
        loop.close()
        #expect(loop === loopOnLoop)
    }

    @Test func testSelect() throws {
        let loop = try SelectorEventLoop.open()
        let thread = FDProvider.get().newThread {
            loop.loop()
        }
        thread.start()

        let tcp = try FDProvider.get().openIPv4Tcp()
        try tcp.setOption(BuiltInSocketOptions.SO_REUSEPORT, true)
        tcp.configureBlocking(false)
        try tcp.bind(GetIPPort(from: "127.0.0.1:22991")!)

        let ctx = CtxForTest()

        try loop.add(tcp, ops: EventSet.read(), attachment: ctx, TcpAcceptHandlerForTest())

        let client = try FDProvider.get().openIPv4Tcp()
        client.configureBlocking(false)
        try client.connect(GetIPPort(from: "127.0.0.1:22991")!)

        try loop.add(client, ops: EventSet.write(), attachment: ctx, TcpEchoHandlerForTest(initiate: true))

        thread.join()

        #expect(ctx.results == ["hello", "hell", "hel", "he", "h"])
    }
}

class CtxForTest {
    var removedCount = 0
    var results = [String](repeating: "", count: 0)
}

class TcpAcceptHandlerForTest: TcpHandler {
    public func readable(_ ctx: HandlerContext) throws {
        let fd = try fd(ctx).accept()
        if fd == nil {
            return
        }
        try ctx.eventLoop.add(fd!, ops: EventSet.read(), attachment: ctx.attachment, TcpEchoHandlerForTest(initiate: false))
    }

    public func writable(_: HandlerContext) throws {
        // will never fire
    }

    public func removed(_ ctx: HandlerContext) throws {
        ctx.fd.close()
    }
}

class TcpEchoHandlerForTest: TcpHandler {
    private var initiate: Bool
    public init(initiate: Bool) {
        self.initiate = initiate
        if initiate {
            let tosend = "hello"
            memcpy(Arrays.getRaw(from: buf), tosend, tosend.count)
            dataLen = tosend.count
        }
    }

    private var buf: [UInt8] = Arrays.newArray(capacity: 16)
    private var dataLen = 0

    public func readable(_ ctx: HandlerContext) throws {
        dataLen = try fd(ctx).read(buf, len: buf.capacity - 1)
        if dataLen < 0 {
            // EOF
            ctx.remove()
            return
        }
        if dataLen <= 0 {
            return
        }
        if dataLen > 0 {
            buf[dataLen] = 0
            (ctx.attachment as! CtxForTest).results.append(String(cString: Arrays.getRaw(from: buf)))
        }
        if dataLen > 1 {
            dataLen -= 1
            try writable(ctx)
        } else {
            ctx.remove()
        }
    }

    public func writable(_ ctx: HandlerContext) throws {
        if initiate {
            try fd(ctx).finishConnect()
            ctx.modify(EventSet.read())
            initiate = false
        }
        _ = try fd(ctx).write(buf, len: dataLen)
    }

    public func removed(_ ctx: HandlerContext) throws {
        ctx.fd.close()
        let c = ctx.attachment as! CtxForTest
        c.removedCount += 1
        if c.removedCount >= 2 {
            ctx.eventLoop.close()
        }
    }
}
