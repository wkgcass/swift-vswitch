import Atomics
import SwiftPriorityQueue
import VProxyCommon

public class SelectorEventLoop {
    private let selector: WrappedSelector
    private let fds: FDs
    private let initOptions: SelectorOptions
    private let timeQueue: any TimeQueue<Runnable> = TimeQueueImpl()
    private let runOnLoopEvents: ConcurrentQueue<Runnable> = ConcurrentQueue()
    private var forEachLoopEvents = [ForEachPollEvent]()

    private var runningThread: (any Thread)?

    private var willClose = false
    private var THE_KEY_SET_BEFORE_SELECTOR_CLOSE: [(any FD, RegisterData)]?

    private var beforePollCallback: (() -> Int)?
    private var afterPollCallback: ((Int, UnsafePointer<FiredExtra>) -> Bool)?
    private var finalizerCallback: (() -> Void)?

    private init(fds: FDs, opts: SelectorOptions) throws(IOException) {
        let fdSelector: FDSelector
        if let optfds = fds as? FDsWithOpts {
            fdSelector = try optfds.openSelector(opts: opts)
        } else {
            fdSelector = try fds.openSelector()
        }
        selector = WrappedSelector(selector: fdSelector)
        self.fds = fds
        initOptions = opts
    }

    public static func open() throws(IOException) -> SelectorEventLoop {
        return try open(opts: SelectorOptions.defaultOpts)
    }

    public static func open(opts: SelectorOptions) throws(IOException) -> SelectorEventLoop {
        return try SelectorEventLoop(fds: FDProvider.get(), opts: opts)
    }

    public static func open(fds: FDs) throws(IOException) -> SelectorEventLoop {
        return try open(fds: fds, opts: SelectorOptions.defaultOpts)
    }

    public static func open(fds: FDs, opts: SelectorOptions) throws(IOException) -> SelectorEventLoop {
        return try SelectorEventLoop(fds: fds, opts: opts)
    }

    public static func current() -> SelectorEventLoop? {
        let thread = FDProvider.get().currentThread()
        return thread?.getLoop()
    }

    private func tryRunnable(_ r: Runnable) {
        do {
            try r.run()
        } catch {
            Logger.error(.IMPROPER_USE, "exception thrown in nextTick event ", error)
        }
    }

    private func handleNonSelectEvents() {
        handleRunOnLoopEvents()
        handleTimeEvents()
        handleForEachLoopEvents()
    }

    public func handleRunOnLoopEvents() {
        let len = runOnLoopEvents.count
        // only run available events when entering this function
        for _ in 0 ..< len {
            let r = runOnLoopEvents.pop()
            if let r {
                tryRunnable(r)
            }
        }
    }

    private func handleTimeEvents() {
        var toRun: [Runnable] = []
        while timeQueue.nextTime(currentTimeMillis: Global.currentTimestamp) == 0 {
            if let r = timeQueue.poll() {
                toRun.append(r)
            }
        }
        for r in toRun {
            tryRunnable(r)
        }
    }

    private func handleForEachLoopEvents() {
        for (idx, e) in forEachLoopEvents.reversed().enumerated() {
            if !e.valid {
                forEachLoopEvents.remove(at: idx)
                continue
            }
            tryRunnable(e.r)
        }
    }

    private func doHandling(_ count: Int) {
        for index in 0 ..< count {
            let key = selectedEntries[index]

            let registerData = Unmanaged<RegisterData>.fromOpaque(key.attachment!).takeUnretainedValue()
            let fd = key.fd
            let handler = registerData.handler

            let ctx = HandlerContext(eventLoop: self, fd: fd, attachment: registerData.att)

            if !fd.isOpen() {
                if selector.isRegistered(fd) {
                    Logger.error(.CONN_ERROR, "channel is closed but still firing: fd = \(fd), event = \(key.ready), attachment = \(String(describing: registerData.att))")
                } // else the channel is closed in another fd handler and removed from loop, this is ok and no need to report
            } else {
                let readyOps = key.ready
                // handle read first because it's most likely to happen
                if readyOps.have(Event.READABLE) {
                    assert(Logger.lowLevelDebug("firing readable for \(fd)"))
                    do {
                        try handler.readable(ctx)
                    } catch {
                        Logger.error(LogType.IMPROPER_USE, "the readable callback got exception", error)
                    }
                }
                // read and write may happen in the same loop round
                if readyOps.have(Event.WRITABLE) {
                    assert(Logger.lowLevelDebug("firing writable for \(fd)"))
                    do {
                        try handler.writable(ctx)
                    } catch {
                        Logger.error(LogType.IMPROPER_USE, "the writable callback got exception", error)
                    }
                }
            }
        }
    }

    private func release() {
        let entries = THE_KEY_SET_BEFORE_SELECTOR_CLOSE
        guard let entries else {
            return
        }
        for e in entries {
            let channel = e.0
            let att = e.1
            triggerRemovedCallback(channel, att)
        }
        runFinalizer()
    }

    public func loop(_ constructThread: (@escaping () -> Void) -> Thread) {
        constructThread(loop).start()
        while runningThread == nil {
            OS.sleep(millis: 1)
        }
    }

    private var selectedEntries: [SelectedEntry] = Arrays.newArray(capacity: 256)

    public func onePoll() -> Int {
        if !selector.isOpen() {
            return -1 // break if it's closed
        }

        // handle some non select events
        Global.currentTimestamp = OS.currentTimeMillis()
        handleNonSelectEvents()

        if willClose {
            closeWithoutConcurrency()
            return -1
        }
        if !selector.isOpen() {
            // do not poll if closed
            return -1
        }

        let maxSleepMillis = runBeforePoll()

        let selected: Int
        do {
            if timeQueue.isEmpty() && runOnLoopEvents.isEmpty() && maxSleepMillis < 0 {
                selected = try selector.select(&selectedEntries) // let it sleep
            } else if !runOnLoopEvents.isEmpty() {
                selected = try selector.selectNow(&selectedEntries) // immediately return when tasks registered into the loop
            } else {
                let time = timeQueue.nextTime(currentTimeMillis: Global.currentTimestamp)
                let finalTime = time > maxSleepMillis && maxSleepMillis >= 0 ? maxSleepMillis : time
                if finalTime == 0 {
                    selected = try selector.selectNow(&selectedEntries) // immediately return
                } else {
                    selected = try selector.select(&selectedEntries, millis: finalTime) // wait until the nearest timer
                }
            }
        } catch {
            return 0
        }

        if !selector.isOpen() {
            return -1 // break if it's closed
        }

        if runAfterPoll() {
            Logger.warn(.ALERT, "event loop terminates because afterPoll callback returns true")
            return -1
        }

        if selected > 0 {
            doHandling(selected)
        }
        return 0
    }

    public func loop() {
        if initOptions.coreAffinity != -1, initOptions.coreAffinity != 0 {
            var set = false
            if let fdsWithAffinity = fds as? FDsWithCoreAffinity {
                do {
                    try fdsWithAffinity.setCoreAffinity(mask: initOptions.coreAffinity)
                    set = true
                } catch {
                    Logger.error(.SYS_ERROR, "setting core affinity to \(initOptions.coreAffinity) failed", error)
                    // just keep running without affinity
                }
            }
            if set {
                Logger.alert("core affinity set: \(initOptions.coreAffinity)")
            } else {
                Logger.warn(LogType.ALERT, "core affinity is not set (\(initOptions.coreAffinity)), continue without core affinity")
            }
        }

        // set thread
        runningThread = fds.currentThread()
        if let runningThread {
            runningThread.setLoop(shouldBeCalledFromSelectorEventLoop: self)
        }
        // run
        while selector.isOpen() {
            if onePoll() == -1 {
                break
            }
        }
        runningThread?.setLoop(shouldBeCalledFromSelectorEventLoop: nil) // remove from thread local
        runningThread = nil // it's not running now, set to null
        // do the final release
        release()
    }

    private func needWake() -> Bool {
        guard let runningThread else {
            // not running yet or not running on vproxy thread
            return true
        }
        let current = fds.currentThread()
        guard let current else {
            // not running on vproxy thread
            return true
        }
        return current.handle() != runningThread.handle()
    }

    public func wakeup() {
        selector.wakeup()
    }

    public func nextTick(_ r: @escaping RunnableFunc) {
        nextTick(Runnable.wrap(r))
    }

    public func nextTick(_ r: Runnable) {
        runOnLoopEvents.push(r)
        if !needWake() {
            return // we do not need to wakeup because it's not started or is already waken up
        }
        wakeup() // wake the selector because new event is added
    }

    public func runOnLoop(_ r: @escaping RunnableFunc) {
        runOnLoop(Runnable.wrap(r))
    }

    public func runOnLoop(_ r: Runnable) {
        if !needWake() {
            tryRunnable(r) // directly run if is already on the loop thread
        } else {
            nextTick(r) // otherwise push into queue
        }
    }

    public func blockUntilFinish(_ r: @escaping () -> Void) {
        if !needWake() {
            r()
            return
        }
        let finished = ManagedAtomic<Bool>(false)
        nextTick {
            r()
            _ = finished.compareExchange(expected: false, desired: true, ordering: .sequentiallyConsistent)
        }
        while !finished.load(ordering: .sequentiallyConsistent) {
            OS.sleep(millis: 1)
        }
    }

    public func forEachLoop(_ e: ForEachPollEvent) {
        runOnLoop { self.forEachLoopEvents.append(e) }
    }

    public func delay(millis: Int, _ r: @escaping RunnableFunc) -> TimerEvent {
        return delay(millis: millis, Runnable.wrap(r))
    }

    public func delay(millis: Int, _ r: Runnable) -> TimerEvent {
        let e = TimerEvent(self)
        // timeQueue is not thread safe
        // modify it in the event loop's thread
        nextTick { e.setEvent(self.timeQueue.add(currentTimeMillis: Global.currentTimestamp,
                                                 timeoutMillis: millis,
                                                 elem: r)) }
        return e
    }

    public func period(intervalMillis: Int, _ r: @escaping RunnableFunc) -> PeriodicEvent {
        return period(intervalMillis: intervalMillis, Runnable.wrap(r))
    }

    public func period(intervalMillis: Int, _ r: Runnable) -> PeriodicEvent {
        let pe = PeriodicEvent(runnable: r, loop: self, intervalMillis: intervalMillis)
        pe.start()
        return pe
    }

    public func add(_ fd: any FD, ops: EventSet, attachment: Any?, _ handler: Handler) throws(IOException) {
        if !fd.isOpen() {
            throw IOException("fd \(fd) is not open")
        }
        if !fd.loopAware(self) {
            throw IOException("fd \(fd) rejects to be attached to current event loop")
        }
        fd.configureBlocking(false)
        let registerData = RegisterData(handler: handler, att: attachment)
        let raw = Unmanaged.passRetained(registerData).toOpaque()

        if initOptions.preferPoll, needWake() {
            runOnLoop {
                try self.selector.register(fd, ops: ops, attachment: raw)
            }
            return
        }
        try selector.register(fd, ops: ops, attachment: raw)
    }

    private func doModify(_ fd: any FD, ops: EventSet) {
        if selector.events(fd) == ops {
            return // no need to update if they are the same
        }

        if initOptions.preferPoll, needWake() {
            runOnLoop {
                self.selector.modify(fd, ops: ops)
            }
            return
        }

        selector.modify(fd, ops: ops)
        if needWake() {
            wakeup()
        }
    }

    public func modify(_ fd: any FD, ops: EventSet) {
        doModify(fd, ops: ops)
    }

    public func addOps(_ fd: any FD, ops: EventSet) {
        let old = selector.events(fd)
        doModify(fd, ops: old.combine(ops))
    }

    public func rmOps(_ fd: any FD, ops: EventSet) {
        let old = selector.events(fd)
        doModify(fd, ops: old.reduce(ops))
    }

    public func remove(_ fd: any FD) {
        if !selector.isRegistered(fd) {
            return
        }

        if initOptions.preferPoll, needWake() {
            runOnLoop {
                let raw = self.selector.remove(fd)!
                let att = Unmanaged<RegisterData>.fromOpaque(raw).takeRetainedValue()
                self.triggerRemovedCallback(fd, att)
            }
            return
        }

        let raw = selector.remove(fd)!
        if needWake() {
            wakeup()
        }

        let att = Unmanaged<RegisterData>.fromOpaque(raw).takeRetainedValue()
        triggerRemovedCallback(fd, att)
    }

    public func getOps(_ fd: any FD) -> EventSet {
        return selector.events(fd)
    }

    public func getAtt(_ fd: any FD) -> Any? {
        let raw = selector.attachment(fd)
        if raw == nil {
            return nil
        }
        let att = Unmanaged<RegisterData>.fromOpaque(raw!).takeUnretainedValue()
        return att.att
    }

    public func getRunningThread() -> Thread? {
        return runningThread
    }

    private func triggerRemovedCallback(_ fd: any FD, _ registerData: RegisterData) {
        let ctx = HandlerContext(eventLoop: self, fd: fd, attachment: registerData.att)
        do {
            try registerData.handler.removed(ctx)
        } catch {
            Logger.error(LogType.IMPROPER_USE, "the removed callback got exception", error)
        }
    }

    public func isClosed() -> Bool {
        return !selector.isOpen()
    }

    public func close(tryJoin: Bool = false) {
        if needWake() {
            closeFromAnotherThread(tryJoin)
        } else {
            willClose = true
        }
    }

    private func closeWithoutConcurrency() {
        willClose = true // ensure it's set
        let keys = selector.entries()

        THE_KEY_SET_BEFORE_SELECTOR_CLOSE = []

        for key in keys {
            let att = Unmanaged<RegisterData>.fromOpaque(key.attachment!).takeRetainedValue()
            THE_KEY_SET_BEFORE_SELECTOR_CLOSE!.append((key.fd, att))
        }

        selector.close()
    }

    private func closeFromAnotherThread(_ tryJoin: Bool) {
        runOnLoop {
            self.willClose = true
        }
        if tryJoin {
            if let runningThread {
                runningThread.join()
            }
        }
    }

    private func runBeforePoll() -> Int {
        guard let beforePollCallback else {
            return -1
        }
        return beforePollCallback()
    }

    public func setBeforePoll(_ cb: @escaping () -> Int) {
        beforePollCallback = cb
    }

    private func runAfterPoll() -> Bool {
        guard let afterPollCallback else {
            return false
        }
        let selector = selector.getSelector()
        let (num, arr) = selector.getFiredExtra()

        return afterPollCallback(num, arr)
    }

    public func setAfterPoll(_ cb: @escaping (Int, UnsafePointer<FiredExtra>) -> Bool) {
        afterPollCallback = cb
    }

    private func runFinalizer() {
        finalizerCallback?()
    }

    public func setFinalizer(_ cb: @escaping () -> Void) {
        finalizerCallback = cb
    }
}

class RegisterData {
    let handler: Handler
    let att: Any?

    init(handler: any Handler, att: Any?) {
        self.handler = handler
        self.att = att
    }
}

public class ForEachPollEvent {
    public var valid = true
    public let r: Runnable
    public init(_ r: Runnable) {
        self.r = r
    }
}
