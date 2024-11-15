#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import VProxyCommonCHelper

let globalExit = exit

public class OS {
    private init() {}

    public static func currentTimeMillis() -> UInt64 {
        var tv = timeval()
        gettimeofday(&tv, nil)
        return UInt64(tv.tv_sec) * 1000 + UInt64(tv.tv_usec / 1000)
    }

    public static func sleep(millis: Int) {
        usleep(useconds_t(millis * 1000))
    }

    public static func exit(code: Int32) {
        globalExit(code)
    }

    public static func gettid() -> UInt64 {
        return swvs_get_tid()
    }
}
