import VProxyCommon

public class FDProvider {
    private nonisolated(unsafe) static var fds: FDs?
    private nonisolated(unsafe) static let lock = Lock()

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

public protocol FDs {
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

    public internal(set) var preferPoll = false
    public internal(set) var coreAffinity: Int64 = -1
    public internal(set) var epfd = 0

    public init() {}
}

public protocol Thread {
    func start()
    func join()

    func setLoop(shouldBeCalledFromSelectorEventLoop loop: SelectorEventLoop?)
    func getLoop() -> SelectorEventLoop?

    func threadlocal(get key: AnyHashable) -> Any?
    func threadlocal(set key: AnyHashable, _ value: Any)

    func handle() -> ThreadHandle
}

public class ThreadHandle: Equatable {
    public init() {}

    public static func == (lhs: ThreadHandle, rhs: ThreadHandle) -> Bool {
        return lhs === rhs
    }
}

public typealias Runnable = () throws -> Void
