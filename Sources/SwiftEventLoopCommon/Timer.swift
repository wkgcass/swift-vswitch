import VProxyCommon

open class Timer {
    private let loop: SelectorEventLoop
    public private(set) var timeoutMillis: Int
    private var lastStart: Int64 = -1
    private var timer: TimerEvent?

    public init(loop: SelectorEventLoop, timeoutMillis: Int) {
        self.loop = loop
        self.timeoutMillis = timeoutMillis
    }

    public func start() {
        if lastStart == -1 {
            resetTimer()
        }
    }

    private func currentTimeMillis() -> Int64 {
        return Int64(Global.currentTimestamp)
    }

    open func resetTimer() {
        if timeoutMillis == -1 {
            return // no timeout
        }
        lastStart = currentTimeMillis()
        if timer == nil {
            timer = loop.delay(millis: timeoutMillis) { self.checkAndCancel() }
        }
    }

    private func checkAndCancel() {
        let current = currentTimeMillis()
        if current - lastStart > Int64(timeoutMillis) {
            cancel()
            return
        }
        let timeLeft = Int64(timeoutMillis) - (current - lastStart)
        timer = loop.delay(millis: Int(timeLeft)) { self.checkAndCancel() }
    }

    open func cancel() {
        lastStart = -1
        if let timer {
            timer.cancel()
            self.timer = nil
        }
    }

    public func setTimeout(millis timeout: Int) {
        if timeoutMillis == timeout {
            return // not changed
        }
        timeoutMillis = timeout
        guard let timer else { // not started yet
            return
        }
        if timeout == -1 { // no timeout
            timer.cancel()
            self.timer = nil
            lastStart = -1
            return
        }
        let current = currentTimeMillis()
        if current - lastStart > Int64(timeout) {
            // should timeout immediately
            // run in next tick to prevent some concurrent modification on sets
            if let currentLoop = SelectorEventLoop.current() {
                currentLoop.nextTick { self.cancel() }
            } else {
                loop.nextTick { self.cancel() }
            }
            return
        }
        timer.cancel()
        let nextDelay = lastStart + Int64(timeout) - current
        lastStart = current
        self.timer = loop.delay(millis: Int(nextDelay)) {
            self.checkAndCancel()
        }
    }

    var ttl: Int64 {
        if lastStart == -1 {
            return -1
        }
        return Int64(timeoutMillis) - (currentTimeMillis() - lastStart)
    }
}
