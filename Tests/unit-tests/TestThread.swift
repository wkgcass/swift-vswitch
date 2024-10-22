import SwiftEventLoopCommon
import SwiftEventLoopPosix
import Testing
import VProxyCommon

struct TestThread {
    init() {
        PosixFDs.setup()
    }

    @Test func testNewThreadAndJoin() {
        var variable = 1
        let thread = FDProvider.get().newThread {
            variable = 2
        }
        thread.start()
        thread.join()
        #expect(variable == 2)
    }

    @Test func testNewThreadSleep() {
        let startTime = OS.currentTimeMillis()
        let thread = FDProvider.get().newThread {
            OS.sleep(millis: 1000)
        }
        thread.start()
        thread.join()
        let endTime = OS.currentTimeMillis()
        #expect(endTime - startTime > 1000)
    }

    @Test func testThreadLocal() {
        var threadObjFromThread: (any SwiftEventLoopCommon.Thread)?
        let thread = FDProvider.get().newThread {
            threadObjFromThread = FDProvider.get().currentThread()
        }
        thread.start()
        thread.join()
        #expect(threadObjFromThread != nil)
        #expect(thread.handle() === threadObjFromThread!.handle())
    }
}
