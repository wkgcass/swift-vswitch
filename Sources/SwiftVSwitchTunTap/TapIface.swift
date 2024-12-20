#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import SwiftEventLoopCommon
import SwiftEventLoopPosix
import SwiftVSwitch
import SwiftVSwitchTunTapCHelper
import VProxyChecksum
import VProxyCommon

public class TapTunFD: PosixFD {
    public static func openTap(dev: String) throws(IOException) -> TapTunFD {
        var tap = swvs_tap_info()
        let ret = swvs_open_tap(dev, 0, &tap)
        if ret != 0 {
            throw IOException("failed to create tap device")
        }
        tap.dev_name.15 = 0
        let p: UnsafePointer<CChar> = Unsafe.ptr2ptrUnsafe(&tap)
        return TapTunFD(fd: tap.fd, dev: String(cString: p))
    }

    public static func openTun(dev: String) throws(IOException) -> TapTunFD {
        var tun = swvs_tap_info()
        let ret = swvs_open_tap(dev, 1, &tun)
        if ret != 0 {
            throw IOException("failed to create tun device")
        }
        tun.dev_name.15 = 0
        let p: UnsafePointer<CChar> = Unsafe.ptr2ptrUnsafe(&tun)
        return TapTunFD(fd: tun.fd, dev: String(cString: p))
    }

    public let dev: String
    init(fd: Int32, dev: String) {
        self.dev = dev
        super.init(fd: fd)
    }
}

public class TapIface: Iface, Hashable {
    let fd: TapTunFD
    public let name: String
    private var ifaceInit_: IfaceInit? = nil
    public var ifaceInit: IfaceInit { ifaceInit_! }
    public var meta: IfaceMetadata

    public static func open(dev: String) throws(IOException) -> TapIface {
        return try TapIface(fd: TapTunFD.openTap(dev: dev))
    }

    private init(fd: TapTunFD) {
        self.fd = fd
        name = "tap:\(fd.dev)"
        meta = IfaceMetadata(
            property: IfaceProperty(layer: .ETHER),
            offload: IfaceOffload(
                rxcsum: .UNNECESSARY,
                txcsum: .COMPLETE
            ),
            initialMac: nil
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

    public func dequeue(_ packets: inout [PacketBuffer], off: inout Int) {
        while true {
            if off >= packets.count {
                break
            }
            let buf = RawBufRef()
            let n: Int
            do {
                n = try fd.read(
                    Unsafe.ptr2mutptr(buf.raw())
                        .advanced(by: VSwitchReservedHeadroom - MemoryLayout<virtio_net_hdr_v1>.stride),
                    len: VSwitchDefaultPacketBufferSize - (VSwitchReservedHeadroom - MemoryLayout<virtio_net_hdr_v1>.stride)
                )
            } catch {
                Logger.error(.SOCKET_ERROR, "failed to read packet from \(fd)", error)
                break
            }
            assert(Logger.lowLevelDebug("read packet of len=\(n)"))
            if n == 0 {
                // nothing read, maybe no packets
                break
            }
            let pkb = PacketBuffer(buf: buf, pktlen: n,
                                   headroom: VSwitchReservedHeadroom,
                                   tailroom: VSwitchDefaultPacketBufferSize - n - VSwitchReservedHeadroom)
            packets[off] = pkb
            off += 1
        }
    }

    public func enqueue(_ pkb: PacketBuffer) -> Bool {
        if pkb.headroom < MemoryLayout<virtio_net_hdr_v1>.stride {
            assert(Logger.lowLevelDebug("no enough headroom for virtio net hdr v1: \(pkb.headroom)"))
            return false
        }
        let hdr: UnsafeMutablePointer<virtio_net_hdr_v1> =
            Unsafe.ptr2mutUnsafe(pkb.raw.advanced(by: -MemoryLayout<virtio_net_hdr_v1>.stride))
        memset(hdr, 0, MemoryLayout<virtio_net_hdr_v1>.stride)

        var out = vproxy_csum_out()
        let err = vproxy_pkt_ether_csum_ex(Unsafe.ptr2mutUnsafe(pkb.raw), Int32(pkb.pktlen), VPROXY_CSUM_IP | VPROXY_CSUM_UP_PSEUDO, &out)
        if err == 0 {
            hdr.pointee.flags = UInt8(VIRTIO_NET_HDR_F_NEEDS_CSUM)
            hdr.pointee.hdr_len = UInt16(pkb.pktlen - pkb.lengthFromAppToEnd)
            hdr.pointee.csum_start = UInt16(Unsafe.ptr2ptrUnsafe(out.up_pos) - pkb.raw)
            hdr.pointee.csum_offset = UInt16(out.up_csum_pos - out.up_pos)
        }
        let writeLen = pkb.pktlen + MemoryLayout<virtio_net_hdr_v1>.stride
        do {
            let n = try fd.write(
                pkb.raw.advanced(by: -MemoryLayout<virtio_net_hdr_v1>.stride),
                len: writeLen
            )
            assert(Logger.lowLevelDebug("wrote packet of len=\(n)"))
            return n == writeLen
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

public class TapIfaceProvider: IfacePerThreadProvider {
    private let devPattern: String
    public init(dev devPattern: String) {
        self.devPattern = devPattern
    }

    public private(set) var name = ""
    private var devName = ""
    public func provide(tid: Int) throws(IOException) -> (any Iface)? {
        if tid == 1 {
            let tap = try TapIface.open(dev: devPattern)
            devName = tap.fd.dev
            name = tap.name
            return tap
        } else {
            return try TapIface.open(dev: devName)
        }
    }
}
