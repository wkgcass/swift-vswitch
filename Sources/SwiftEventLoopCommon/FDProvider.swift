import VProxyCommon

public class FDProvider {
    private nonisolated(unsafe) static var fds: FDs?
    private nonisolated(unsafe) static var lock = Lock()

    public static func get() -> FDs {
        return fds!
    }

    public static func setShouldOnlyBeCalledFromEventLoopProvider(_ provider: (FDs?) -> FDs?) {
        lock.lock()
        defer { lock.unlock() }

        let newfds = provider(fds)
        if newfds == nil {
            return
        }
        FDProvider.fds = newfds
    }
}

public protocol FDs: AnyObject {
    func newThread(_ runnable: @escaping () -> Void) -> any Thread
    func currentThread() -> (any Thread)?

    func openSelector() throws(IOException) -> FDSelector
    func openIPv4Tcp() throws(IOException) -> any TcpFD
    func openIPv6Tcp() throws(IOException) -> any TcpFD
    func openIPv4Udp() throws(IOException) -> any UdpFD
    func openIPv6Udp() throws(IOException) -> any UdpFD
}

public protocol FDsWithOpts: FDs {
    func openSelector(opts: SelectorOptions) throws(IOException) -> FDSelector
}

public protocol FDsWithCoreAffinity: FDs {
    func setCoreAffinity(mask: Int64) throws
}

public struct SelectorOptions: Sendable {
    public static let defaultOpts = SelectorOptions()

    public var preferPoll = false
    public var coreAffinity: Int64 = -1
    public var epfd = 0

    public init() {}
}

public let ThreadMemPoolArraySize = 2048
public let ThreadMemPoolCount = 8192

public protocol Thread: AnyObject {
    func start()
    func join()

    func setLoop(shouldBeCalledFromSelectorEventLoop loop: SelectorEventLoop?)
    func getLoop() -> SelectorEventLoop?
    var memPool: FixedSizeFixedCountSingleThreadMemPool { get }

    func handle() -> ThreadHandle
}

public class ThreadHandle: Equatable {
    public init() {}

    public static func == (lhs: ThreadHandle, rhs: ThreadHandle) -> Bool {
        return lhs === rhs
    }
}

open class Runnable {
    open func run() throws {}
    public static func wrap(_ f: @escaping RunnableFunc) -> Runnable { RunnableFuncWrap(f) }
}

class RunnableFuncWrap: Runnable {
    private let f: RunnableFunc
    init(_ f: @escaping RunnableFunc) {
        self.f = f
    }

    override public func run() throws {
        try f()
    }
}

public typealias RunnableFunc = () throws -> Void
