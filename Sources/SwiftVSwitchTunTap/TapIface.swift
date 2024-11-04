import SwiftEventLoopCommon
import SwiftEventLoopPosix
import SwiftVSwitch
import SwiftVSwitchTunTapCHelper
import VProxyCommon

public class TapTunFD: PosixFD {
    public static func openTap(dev: String) throws -> TapTunFD {
        var tap = swvs_tap_info()
        let ret = swvs_open_tap(dev, 0, &tap)
        if ret != 0 {
            throw IOException("failed to create tap device")
        }
        tap.dev_name.15 = 0
        let p: UnsafePointer<CChar> = Convert.ptr2ptrUnsafe(&tap)
        return TapTunFD(fd: tap.fd, dev: String(cString: p))
    }

    public let dev: String
    init(fd: Int32, dev: String) {
        self.dev = dev
        super.init(fd: fd)
    }
}

public class TapIface: Iface, Hashable {
    private let fd: TapTunFD
    public let name: String
    public var statistics = IfaceStatistics()
    public var offload: IfaceOffload
    private var ifaceInit_: IfaceInit? = nil
    public var ifaceInit: IfaceInit { ifaceInit_! }

    public static func open(dev: String) throws -> TapIface {
        return try TapIface(fd: TapTunFD.openTap(dev: dev))
    }

    init(fd: TapTunFD) {
        self.fd = fd
        name = "tap:\(fd.dev)"
        offload = IfaceOffload(
            rxcsum: .UNNECESSARY,
            txcsum: .NONE
        )
    }

    public func initialize(_ ifaceInit: IfaceInit) throws(IOException) {
        try ifaceInit.loop.add(fd, ops: EventSet.read(), attachment: nil, DoNothingHandler())
        ifaceInit_ = ifaceInit
    }

    public func close() {
        if let ifaceInit = ifaceInit_ {
            ifaceInit.loop.remove(fd)
        }
        fd.close()
    }

    private var lastBuf: [UInt8]? = nil

    public func dequeue(_ packets: inout [PacketBuffer], off: inout Int) {
        while true {
            if off >= packets.count {
                break
            }
            var buf: [UInt8]
            if lastBuf == nil {
                buf = Arrays.newArray(capacity: VSwitchDefaultPacketBufferSize)
            } else {
                buf = lastBuf!
                lastBuf = nil
            }
            let n: Int
            do {
                n = try fd.read(&buf, off: VSwitchReservedHeadroom, len: VSwitchDefaultPacketBufferSize - VSwitchReservedHeadroom)
            } catch {
                Logger.error(.SOCKET_ERROR, "failed to read packet from \(fd)", error)
                break
            }
            assert(Logger.lowLevelDebug("read packet of len=\(n)"))
            if n == 0 {
                lastBuf = buf
                // nothing read, maybe no packets
                break
            }
            let pkb = PacketBuffer(packetArray: buf,
                                   offset: 0,
                                   pktlen: n,
                                   headroom: VSwitchReservedHeadroom,
                                   tailroom: VSwitchDefaultPacketBufferSize - n - VSwitchReservedHeadroom)
            packets[off] = pkb
            off += 1
        }
    }

    public func enqueue(_ pkb: PacketBuffer) -> Bool {
        do {
            let n = try fd.write(pkb.raw, off: 0, len: pkb.pktlen)
            assert(Logger.lowLevelDebug("wrote packet of len=\(n)"))
            return n == pkb.pktlen
        } catch {
            Logger.error(.SOCKET_ERROR, "failed to send packet to \(fd)", error)
            return false
        }
    }

    public func completeTx() {
        // do nothing
    }

    public func hash(into hasher: inout Hasher) {
        fd.hash(into: &hasher)
    }

    private var handle_: IfaceHandle? = nil
    public func handle() -> IfaceHandle {
        guard let handle_ else {
            let h = IfaceHandle(iface: self)
            self.handle_ = h
            return h
        }
        return handle_
    }

    public static func == (lhs: TapIface, rhs: TapIface) -> Bool {
        return lhs.handle() == rhs.handle()
    }
}
