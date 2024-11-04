#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import SwiftEventLoopCommon
import SwiftEventLoopPosixCHelper
import VProxyCommon

public class PosixFDs: FDs, FDsWithOpts, FDsWithCoreAffinity {
    private var threadLocalKey = pthread_key_t()

    private init() {
        pthread_key_create(&threadLocalKey, nil)
    }

    public static func setup() {
        FDProvider.setShouldOnlyBeCalledFromEventLoopProvider { fds in
            if fds != nil && fds is PosixFDs {
                return nil
            }
            return PosixFDs()
        }
    }

    public func newThread(_ runnable: @escaping () -> Void) -> any Thread {
        return PThread(self, runnable)
    }

    public func currentThread() -> (any Thread)? {
        let raw = getThreadLocal()
        guard let raw else {
            return nil
        }
        let v = Unmanaged<PThread>.fromOpaque(raw).takeUnretainedValue()
        return v
    }

    public func setCoreAffinity(mask: Int64) throws(IOException) {
#if os(Linux)
        var errno: Int32 = 0
        let err = swvs_set_core_affinity(mask, &errno)
        if err == 0 {
            return
        }
        throw IOException("failed to set core affinity", errno: errno)
#else
        // TODO: implement for macos
        throw IOException("current platform doesn't support setting core affinity")
#endif
    }

    func setThreadLocal(_ p: UnsafeRawPointer?) {
        pthread_setspecific(threadLocalKey, p)
    }

    func getThreadLocal() -> UnsafeMutableRawPointer? {
        return pthread_getspecific(threadLocalKey)
    }

    public func openSelector() throws(IOException) -> FDSelector {
        return try AESelector()
    }

    public func openSelector(opts: SelectorOptions) throws(IOException) -> FDSelector {
        return try AESelector(opts: opts)
    }

    public func openIPv4Tcp() throws(IOException) -> any TcpFD {
        return try TCPPosixFD.openIPv4()
    }

    public func openIPv6Tcp() throws(IOException) -> any TcpFD {
        return try TCPPosixFD.openIPv6()
    }

    public func openIPv4Udp() throws(IOException) -> any UdpFD {
        return try UDPPosixFD.openIPv4()
    }

    public func openIPv6Udp() throws(IOException) -> any UdpFD {
        return try UDPPosixFD.openIPv6()
    }
}

#if os(Linux)
let globalBind = SwiftGlibc.bind
#else
let globalBind = bind
#endif
let IP_TRANSPARENT: Int32 = 19
let SOL_IP: Int32 = 0

open class PosixFD: FD, CustomStringConvertible {
    public typealias HandleType = FDHandle

    let fd: Int32
    private var isOpen_: Bool
    private var handle_: FDHandle? = nil

    public init(fd: Int32) {
        self.fd = fd
        isOpen_ = true
    }

    public func isOpen() -> Bool {
        return isOpen_
    }

    public func configureBlocking(_ b: Bool) {
        let blocking: Int32 = if b { 1 } else { 0 }
        let v = swvs_configureBlocking(fd, blocking)
        if v < 0 {
            Logger.error(.SOCKET_ERROR, "failed to set fd flags when trying to configure blocking on \(fd) \(b)")
        }
    }

    public func setOption<T>(_ name: SocketOption<T>, _ value: T) throws(IOException) -> Void {
        if T.self == Int.self {
            let iname = name as! SocketOption<Int>
            var n: Int = value as! Int
            if iname == SockOpts.SO_LINGER {
                var lingerValue = linger(l_onoff: 1, l_linger: Int32(n))
                let err = setsockopt(fd, SOL_SOCKET, SO_LINGER, &lingerValue, socklen_t(MemoryLayout<linger>.stride))
                try handleSetSockOptErr(err, "failed to set linger \(value) to \(fd)")
                return
            } else if iname == SockOpts.SO_RCVBUF {
                let err = setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &n, 4)
                try handleSetSockOptErr(err, "failed to set rcvbuf \(n) to \(fd)")
                return
            }
        } else if T.self == Bool.self {
            let b = value as! Bool
            var n: Int32 = if b { 1 } else { 0 }
            let bname = name as! SocketOption<Bool>
            if bname == SockOpts.SO_REUSEPORT {
                let err = setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &n, 4)
                try handleSetSockOptErr(err, "failed to set reuseport \(b) to \(fd)")
                return
            } else if bname == SockOpts.SO_REUSEADDR {
                let err = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &n, 4)
                try handleSetSockOptErr(err, "failed to set reuseaddr \(b) to \(fd)")
                return
            } else if bname == SockOpts.SO_BROADCAST {
                let err = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &n, 4)
                try handleSetSockOptErr(err, "failed to set broadcast \(b) to \(fd)")
                return
            } else if bname == SockOpts.TCP_NODELAY {
                let err = setsockopt(fd, SOL_SOCKET, TCP_NODELAY, &n, 4)
                try handleSetSockOptErr(err, "failed to set tcp nodelay \(b) to \(fd)")
                return
            } else if bname == SockOpts.IP_TRANSPARENT {
                let err = setsockopt(fd, SOL_IP, IP_TRANSPARENT, &n, 4)
                try handleSetSockOptErr(err, "failed to set ip transparent \(b) to \(fd)")
                return
            }
        }
        throw IOException("unknown SocketOption")
    }

    private func handleSetSockOptErr(_ err: Int32, _ msg: String) throws(IOException) {
        if err == 0 {
            return
        }
        throw IOException(msg)
    }

    public func write(_ buf: [UInt8], len: Int) throws(IOException) -> Int {
        return try write(buf, off: 0, len: len)
    }

    public func write(_ buf: [UInt8], off: Int, len: Int) throws(IOException) -> Int {
        return try write(Arrays.getRaw(from: buf), off: off, len: len)
    }

    public func write(_ buf: UnsafePointer<UInt8>, off: Int, len: Int) throws(IOException) -> Int {
        var errno: Int32 = 0
        let n = writeWithErrno(fd, buf.advanced(by: off), len, &errno)
        if n < 0 {
            if errno == EWOULDBLOCK {
                return 0
            }
            throw IOException("failed to write to \(fd)", errno: errno)
        }
        return n
    }

    public func read(_ buf: inout [UInt8], len: Int) throws(IOException) -> Int {
        return try read(&buf, off: 0, len: len)
    }

    public func read(_ buf: inout [UInt8], off: Int = 0, len: Int) throws(IOException) -> Int {
        var errno: Int32 = 0
        let n = readWithErrno(fd, Arrays.getRaw(from: buf, offset: off), len, &errno)
        if n < 0 {
            if errno == EWOULDBLOCK {
                return 0
            }
            throw IOException("failed to read from \(fd)", errno: errno)
        }
        if n == 0 {
            return -1
        }
        return n
    }

    public func close() {
        _ = globalClose(fd)
        handle_ = nil // release refcnt
    }

    public func contains(_ fd: any FD) -> Bool {
        return handle() == fd.handle()
    }

    public func handle() -> HandleType {
        if handle_ == nil {
            handle_ = FDHandle(self)
        }
        return handle_!
    }

    public var description: String {
        return "PosixFD(\(fd))"
    }

    public static func == (lhs: PosixFD, rhs: PosixFD) -> Bool {
        return lhs === rhs
    }

    public var hashValue: Int {
        return fd.hashValue
    }

    public func hash(into hasher: inout Hasher) {
        fd.hash(into: &hasher)
    }
}

public class InetPosixFD: PosixFD, InetFD {
    let af: Int32
    public init(fd: Int32, af: Int32) {
        self.af = af
        super.init(fd: fd)
    }

    public func bind(_ ipport: IPPort) throws(IOException) {
        var (n, addr) = ipport.toGeneralSockAddr()
        let err = globalBind(fd, Convert.ptr2ptrUnsafe(&addr), n)
        if err != 0 {
            throw IOException("failed to bind \(ipport)")
        }
        let backlog: Int32 = 128
        _ = listen(fd, backlog) // maybe udp, so ignore error
    }

    public func connect(_ ipport: IPPort) throws(IOException) {
        var (n, addr) = ipport.toGeneralSockAddr()
        var errno: Int32 = 0
        let err = connectWithErrno(fd, Convert.ptr2ptrUnsafe(&addr), n, &errno)
        if err != 0 {
            if errno == EWOULDBLOCK || errno == EINPROGRESS {
                return
            }
            throw IOException("failed to connect to \(ipport)", errno: errno)
        }
    }

    private var remoteAddress_: (any IPPort)? = nil
    private var localAddress_: (any IPPort)? = nil

    public var remoteAddress: any IPPort {
        if let remoteAddress_ {
            return remoteAddress_
        }

        let res: any IPPort
        if af == AF_INET {
            var addr = sockaddr_in()
            var len = UInt32(MemoryLayout<sockaddr_in>.stride)
            getpeername(fd, Convert.mut2mutUnsafe(&addr), &len)
            res = IPv4Port(IPv4(raw: &addr.sin_addr), Convert.reverseByteOrder(addr.sin_port))
        } else {
            var addr = sockaddr_in6()
            var len = UInt32(MemoryLayout<sockaddr_in6>.stride)
            getpeername(fd, Convert.mut2mutUnsafe(&addr), &len)
            res = IPv6Port(IPv6(raw: &addr.sin6_addr), Convert.reverseByteOrder(addr.sin6_port))
        }
        localAddress_ = res
        return res
    }

    public var localAddress: any IPPort {
        if let localAddress_ {
            return localAddress_
        }

        let res: any IPPort
        if af == AF_INET {
            var addr = sockaddr_in()
            var len = UInt32(MemoryLayout<sockaddr_in>.stride)
            getsockname(fd, Convert.mut2mutUnsafe(&addr), &len)
            res = IPv4Port(IPv4(raw: &addr.sin_addr), Convert.reverseByteOrder(addr.sin_port))
        } else {
            var addr = sockaddr_in6()
            var len = UInt32(MemoryLayout<sockaddr_in6>.stride)
            getsockname(fd, Convert.mut2mutUnsafe(&addr), &len)
            res = IPv6Port(IPv6(raw: &addr.sin6_addr), Convert.reverseByteOrder(addr.sin6_port))
        }
        localAddress_ = res
        return res
    }
}

public class StreamPosixFD: InetPosixFD, StreamFD {
    func formatAcceptedStreamFD(fd _: Int32) -> (any StreamFD)? {
        return nil
    }

    public func accept() throws(IOException) -> (any StreamFD)? {
        var errno: Int32 = 0
        let fd = acceptWithErrno(fd, nil, nil, &errno)
        if fd < 0 {
            if errno == EWOULDBLOCK {
                return nil
            }
            throw IOException("failed to accept fd", errno: errno)
        }
        return formatAcceptedStreamFD(fd: fd)
    }

    public func shutdownOutput() {
        _ = shutdown(fd, Int32(SHUT_WR))
    }
}

public class DatagramPosixFD: InetPosixFD, DatagramFD {
    public func recv(_ buf: inout [UInt8], len: Int) throws(IOException) -> (Int, IPPort?) {
        return try recv(&buf, off: 0, len: len)
    }

    public func recv(_ buf: inout [UInt8], off: Int, len: Int) throws(IOException) -> (Int, IPPort?) {
        var errno: Int32 = 0
        let n: Int
        let res: any IPPort
        if af == AF_INET {
            var addr = sockaddr_in()
            var sz = UInt32(MemoryLayout<sockaddr_in6>.stride)
            n = recvfromWithErrno(fd, Arrays.getRaw(from: buf, offset: off), len, 0, Convert.mut2mutUnsafe(&addr), &sz, &errno)
            res = IPv4Port(IPv4(raw: &addr.sin_addr), Convert.reverseByteOrder(addr.sin_port))
        } else {
            var addr = sockaddr_in6()
            var sz = UInt32(MemoryLayout<sockaddr_in6>.stride)
            n = recvfromWithErrno(fd, Arrays.getRaw(from: buf, offset: off), len, 0, Convert.mut2mutUnsafe(&addr), &sz, &errno)
            res = IPv6Port(IPv6(raw: &addr.sin6_addr), Convert.reverseByteOrder(addr.sin6_port))
        }
        if n < 0 {
            if errno == EWOULDBLOCK {
                return (0, nil)
            }
            throw IOException("failed to recv", errno: errno)
        }
        return (n, res)
    }

    public func send(_ buf: [UInt8], len: Int, remote: any IPPort) throws(IOException) -> Int {
        return try send(buf, off: 0, len: len, remote: remote)
    }

    public func send(_ buf: [UInt8], off: Int, len: Int, remote: any IPPort) throws(IOException) -> Int {
        var errno: Int32 = 0
        var (addrlen, addr) = remote.toGeneralSockAddr()
        let n = sendtoWithErrno(fd, Arrays.getRaw(from: buf, offset: off), len, 0, Convert.mut2mutUnsafe(&addr), addrlen, &errno)
        if n < 0 {
            if errno == EWOULDBLOCK {
                return 0
            }
            throw IOException("failed to write", errno: errno)
        }
        return n
    }
}

public class TCPPosixFD: StreamPosixFD, TcpFD {
    public static func openIPv4() throws(IOException) -> TCPPosixFD {
#if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
#else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
#endif
        if fd < 0 {
            throw IOException("unable to open ipv4 tcp socket")
        }
        return TCPPosixFD(fd: fd, af: AF_INET)
    }

    public static func openIPv6() throws(IOException) -> TCPPosixFD {
#if os(Linux)
        let fd = socket(AF_INET6, Int32(SOCK_STREAM.rawValue), 0)
#else
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
#endif
        if fd < 0 {
            throw IOException("unable to open ipv6 tcp socket")
        }
        return TCPPosixFD(fd: fd, af: AF_INET6)
    }

    override func formatAcceptedStreamFD(fd: Int32) -> (any StreamFD)? {
        return TCPPosixFD(fd: fd, af: af)
    }
}

public class UDPPosixFD: DatagramPosixFD, UdpFD {
    public static func openIPv4() throws(IOException) -> UDPPosixFD {
#if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
#else
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
#endif
        if fd < 0 {
            throw IOException("unable to open ipv4 udp socket")
        }
        return UDPPosixFD(fd: fd, af: AF_INET)
    }

    public static func openIPv6() throws(IOException) -> UDPPosixFD {
#if os(Linux)
        let fd = socket(AF_INET6, Int32(SOCK_DGRAM.rawValue), 0)
#else
        let fd = socket(AF_INET6, SOCK_DGRAM, 0)
#endif
        if fd < 0 {
            throw IOException("unable to open ipv6 udp socket")
        }
        return UDPPosixFD(fd: fd, af: AF_INET6)
    }
}
