import VProxyCommon

public protocol FD<HandleType>: Equatable, Hashable {
    associatedtype HandleType: FDHandle

    func isOpen() -> Bool
    func configureBlocking(_ b: Bool)
    func setOption<T>(_ name: SocketOption<T>, _ value: T) throws(IOException) -> Void
    func close()
    func real() -> any FD
    func contains(_ fd: any FD) -> Bool
    func loopAware(_ loop: SelectorEventLoop) -> Bool
    func handle() -> HandleType

    func write(_ buf: [UInt8], len: Int) throws(IOException) -> Int
    func write(_ buf: [UInt8], off: Int, len: Int) throws(IOException) -> Int
    func read(_ buf: [UInt8], len: Int) throws(IOException) -> Int
    func read(_ buf: [UInt8], off: Int, len: Int) throws(IOException) -> Int
}

public protocol InetFD: FD {
    func bind(_ ipport: IPPort) throws(IOException)
    func connect(_ ipport: IPPort) throws(IOException)
    var localAddress: IPPort { get }
    var remoteAddress: IPPort { get }
}

public protocol StreamFD: InetFD {
    func accept() throws(IOException) -> (any StreamFD)?
    func finishConnect() throws(IOException)
    func shutdownOutput()
}

public protocol TcpFD: StreamFD {}

public protocol DatagramFD: InetFD {
    func recv(_ buf: [UInt8], len: Int) throws(IOException) -> (Int, IPPort?)
    func recv(_ buf: [UInt8], off: Int, len: Int) throws(IOException) -> (Int, IPPort?)
    func send(_ buf: [UInt8], len: Int, remote: IPPort) throws(IOException) -> Int
    func send(_ buf: [UInt8], off: Int, len: Int, remote: IPPort) throws(IOException) -> Int
}

public protocol UdpFD: DatagramFD {}

public extension FD {
    func loopAware(_: SelectorEventLoop) -> Bool {
        return true
    }

    static func == (lhs: any FD, rhs: any FD) -> Bool {
        return lhs.handle() == rhs.handle()
    }
}

public protocol VirtualFD: FD where HandleType: VirtualFDHandle {
    func onRegister()
    func onRemove()
}

public class FDHandle: Equatable, Hashable {
    let fd_: any FD

    public init(_ fd: any FD) {
        fd_ = fd
    }

    public func fd() -> any FD {
        return fd_
    }

    public var hashValue: Int {
        fd_.hashValue
    }

    public func hash(into hasher: inout Hasher) {
        fd_.hash(into: &hasher)
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
