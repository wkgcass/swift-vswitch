import VProxyCommon

public class PeriodicEvent {
    private let runnable: Runnable
    private let loop: SelectorEventLoop
    private let delay: Int
    private var running = false
    private var te: TimerEvent?

    init(runnable: Runnable, loop: SelectorEventLoop, delayMillis: Int) {
        self.runnable = runnable
        self.loop = loop
        delay = delayMillis
    }

    // No need to handle concurrency of this function
    // It's only called once and called on event loop
    func start() {
        running = true
        te = loop.delay(delay, Runnable {
            self.run()
        })
    }

    private func run() {
        if running {
            do {
                try runnable.run()
            } catch {
                Logger.error(.IMPROPER_USE, "error thrown in periodic event")
            }
            // At this time, it might be canceled
            if running {
                te = loop.delay(delay, Runnable {
                    self.run()
                })
            } else {
                te = nil // Set to nil in case of concurrency
            }
        } else {
            te = nil // Set to nil in case of concurrency
        }
    }

    func cancel() {
        running = false
        if te != nil {
            te!.cancel()
        }
        te = nil
    }
}
