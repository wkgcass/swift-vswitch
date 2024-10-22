#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct IOException: Error {
    public let message: String

    public init(_ msg: String) {
        message = msg
    }

    public init(_ msg: String, errno: Int32) {
        let m = msg + ": \(errno)\(String(cString: strerror(errno)))"
        self.init(m)
    }
}
