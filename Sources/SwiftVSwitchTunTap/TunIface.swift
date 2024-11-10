#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import SwiftEventLoopCommon
import SwiftEventLoopPosix
import SwiftVSwitch
import SwiftVSwitchTunTapCHelper
import VProxyCommon

public class TunIface: Iface, Hashable {
    private let fd: TapTunFD
    public let name: String
    private var ifaceInit_: IfaceInit? = nil
    public var ifaceInit: IfaceInit { ifaceInit_! }
    public var meta: IfaceMetadata

    public static func open(dev: String) throws -> TunIface {
        return try TunIface(fd: TapTunFD.openTun(dev: dev))
    }

    private init(fd: TapTunFD) {
        self.fd = fd
        name = "tun:\(fd.dev)"
        meta = IfaceMetadata(
            property: IfaceProperty(layer: .IP),
            offload: IfaceOffload(
                rxcsum: .UNNECESSARY,
                txcsum: .NONE
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
            var readOff = VSwitchReservedHeadroom
#if os(Linux)
#else
            readOff -= 4
#endif
            let n: Int
            do {
                n = try fd.read(Convert.ptr2mutptr(buf.raw()).advanced(by: readOff), len: VSwitchDefaultPacketBufferSize - readOff)
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
                                   tailroom: VSwitchDefaultPacketBufferSize - n - VSwitchReservedHeadroom,
                                   hasEthernet: false)
            packets[off] = pkb
            off += 1
        }
    }

    public func enqueue(_ pkb: PacketBuffer) -> Bool {
        guard let ipPkt = pkb.ip else {
            assert(Logger.lowLevelDebug("ip packet is not found"))
            return false
        }
        var pktlen = pkb.pktlen - (ipPkt - pkb.raw)
        let ver = (ipPkt.pointee >> 4) & 0xf

        var raw: UnsafeMutablePointer<UInt8>
#if os(Linux)
        raw = Convert.ptr2mutptr(ipPkt)
#else
        if ipPkt - pkb.raw + pkb.headroom < 4 {
            assert(Logger.lowLevelDebug("no enough room for af header"))
            return false
        } else {
            raw = Convert.ptr2mutptr(ipPkt.advanced(by: -4))
        }
        pktlen += 4
        raw.pointee = 0
        raw.advanced(by: 1).pointee = 0
        raw.advanced(by: 2).pointee = 0
        if ver == 4 {
            raw.advanced(by: 3).pointee = UInt8(AF_INET)
        } else {
            raw.advanced(by: 3).pointee = UInt8(AF_INET6)
        }
#endif
        do {
            let n = try fd.write(raw, len: pktlen)
            assert(Logger.lowLevelDebug("wrote packet of len=\(n)"))
            return n == pktlen
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

    public static func == (lhs: TunIface, rhs: TunIface) -> Bool {
        return lhs.handle() == rhs.handle()
    }
}
