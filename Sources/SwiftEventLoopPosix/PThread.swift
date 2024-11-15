import SwiftEventLoopCommon
import SwiftEventLoopPosixCHelper
import VProxyCommon

let thread_entry_func: @convention(c) (_ p: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? = { p in
    let ctx: ThreadStartContext = Unsafe.convertFromNativeDecRef(p!)
    let retained = Unmanaged.passRetained(ctx.thread)
    ctx.fds.setThreadLocal(retained.toOpaque())
    ctx.runnable()
    retained.release()
    return nil
}

class ThreadStartContext {
    let thread: PThread
    let fds: PosixFDs
    let runnable: () -> Void
    init(thread: PThread, fds: PosixFDs, runnable: @escaping () -> Void) {
        self.thread = thread
        self.fds = fds
        self.runnable = runnable
    }
}

class PThread: Thread {
    private let handle_ = ThreadHandle()
    private let fds: PosixFDs
    private let runnable: () -> Void
    private var thread = swvs_thread_t()

    private var loop_: SelectorEventLoop? = nil

    init(_ fds: PosixFDs, _ runnable: @escaping () -> Void) {
        self.fds = fds
        self.runnable = runnable
    }

    public func start() {
        let ctx = ThreadStartContext(thread: self, fds: fds, runnable: runnable)
        let ud = Unmanaged.passRetained(ctx).toOpaque()
        swvs_start_thread(&thread, thread_entry_func, ud)
    }

    public func join() {
        pthread_join(thread.thread, nil)
    }

    public func setLoop(shouldBeCalledFromSelectorEventLoop loop: SelectorEventLoop?) {
        loop_ = loop
    }

    public func getLoop() -> SelectorEventLoop? {
        return loop_
    }

    public let memPool = FixedSizeFixedCountSingleThreadMemPool(size: ThreadMemPoolArraySize, count: ThreadMemPoolCount)!

    public func handle() -> ThreadHandle {
        return handle_
    }
}
