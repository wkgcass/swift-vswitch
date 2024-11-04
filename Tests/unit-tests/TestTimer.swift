import SwiftEventLoopCommon
import SwiftEventLoopPosix
import Testing
import VProxyCommon

class TestTimer {
    init() {
        PosixFDs.setup()
    }

    @Test func delay() throws {
        let loop = try SelectorEventLoop.open()
        let thread = FDProvider.get().newThread { loop.loop() }
        thread.start()

        let begin = OS.currentTimeMillis()
        _ = loop.delay(millis: 1000) { loop.close() }
        thread.join()
        let after = OS.currentTimeMillis()

        #expect(after - begin >= 1000)
    }

    @Test func cancelDelay() throws {
        let loop = try SelectorEventLoop.open()
        let thread = FDProvider.get().newThread { loop.loop() }
        thread.start()

        let begin = OS.currentTimeMillis()
        let delay1 = loop.delay(millis: 500) { loop.close() }
        _ = loop.delay(millis: 1000) { loop.close() }

        OS.sleep(millis: 100)
        delay1.cancel()
        thread.join()
        let after = OS.currentTimeMillis()

        #expect(after - begin >= 1000)
    }

    @Test func periodic() throws {
        let loop = try SelectorEventLoop.open()
        let thread = FDProvider.get().newThread { loop.loop() }
        thread.start()

        let begin = OS.currentTimeMillis()
        var n = 0
        _ = loop.period(intervalMillis: 200) {
            n += 1
            if n >= 5 {
                loop.close()
            }
        }

        thread.join()
        let after = OS.currentTimeMillis()

        #expect(after - begin > 1000 && after - begin < 1200)
    }

    @Test func cancelPeriodic() throws {
        let loop = try SelectorEventLoop.open()
        let thread = FDProvider.get().newThread { loop.loop() }
        thread.start()

        var n = 0
        let periodic = loop.period(intervalMillis: 100) { n += 1 }

        OS.sleep(millis: 550)
        periodic.cancel()

        OS.sleep(millis: 1000)
        #expect(n == 5)
        loop.close(tryJoin: true)
    }
}
