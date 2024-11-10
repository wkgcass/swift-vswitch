import VProxyCommon

public protocol FD<HandleType>: Equatable, Hashable, AnyObject {
    associatedtype HandleType: FDHandle

    func isOpen() -> Bool
    func configureBlocking(_ b: Bool)
    func setOption<T>(_ name: SocketOption<T>, _ value: T) throws(IOException) -> Void
    func close() // NOTE: remember to release refcnt to handle
    func contains(_ fd: any FD) -> Bool
    func loopAware(_ loop: SelectorEventLoop) -> Bool
    func handle() -> HandleType

    func write(_ buf: [UInt8], len: Int) throws(IOException) -> Int
    func write(_ buf: [UInt8], off: Int, len: Int) throws(IOException) -> Int
    func write(_ buf: UnsafeRawPointer, len: Int) throws(IOException) -> Int
    func read(_ buf: inout [UInt8], len: Int) throws(IOException) -> Int
    func read(_ buf: inout [UInt8], off: Int, len: Int) throws(IOException) -> Int
    func read(_ buf: UnsafeMutableRawPointer, len: Int) throws(IOException) -> Int
}

public extension FD {
    func loopAware(_: SelectorEventLoop) -> Bool {
        return true
    }

    static func == (lhs: any FD, rhs: any FD) -> Bool {
        return lhs.handle() == rhs.handle()
    }
}

public protocol InetFD: FD {
    func bind(_ ipport: any IPPort) throws(IOException)
    func connect(_ ipport: any IPPort) throws(IOException)
    var localAddress: any IPPort { get }
    var remoteAddress: any IPPort { get }
}

public protocol StreamFD: InetFD {
    func accept() throws(IOException) -> (any StreamFD)?
    func shutdownOutput()
}

let BUF_FOR_FINISH_CONNECT: [UInt8] = Arrays.newArray(capacity: 1, uninitialized: true)

public extension StreamFD {
    func finishConnect() throws(IOException) {
        _ = try write(BUF_FOR_FINISH_CONNECT, len: 0)
    }
}

public protocol TcpFD: StreamFD {}

public protocol DatagramFD: InetFD {
    func recv(_ buf: inout [UInt8], len: Int) throws(IOException) -> (Int, any IPPort)?
    func recv(_ buf: inout [UInt8], off: Int, len: Int) throws(IOException) -> (Int, any IPPort)?
    func send(_ buf: [UInt8], len: Int, remote: any IPPort) throws(IOException) -> Int
    func send(_ buf: [UInt8], off: Int, len: Int, remote: any IPPort) throws(IOException) -> Int
}

public protocol UdpFD: DatagramFD {}

public protocol VirtualFD: FD where HandleType: VirtualFDHandle {
    func onRegister()
    func onRemove()
}

public class FDHandle: Equatable, Hashable {
    public let fd: any FD

    public init(_ fd: any FD) {
        self.fd = fd
    }

    public var hashValue: Int {
        fd.hashValue
    }

    public func hash(into hasher: inout Hasher) {
        fd.hash(into: &hasher)
    }

    public static func == (lhs: FDHandle, rhs: FDHandle) -> Bool {
        return lhs === rhs
    }
}

public class VirtualFDHandle: FDHandle {
    public init(fd: any VirtualFD) {
        super.init(fd)
    }
}
