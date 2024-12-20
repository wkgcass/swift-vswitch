import SwiftEventLoopCommon
import VProxyCommon

public protocol Iface: AnyObject, CustomStringConvertible, Hashable {
    var name: String { get }
    func initialize(_ ifaceInit: IfaceInit) throws(IOException)
    func close() // don't forget to release the handle pointer

    func dequeue(_ packets: inout [PacketBuffer], off: inout Int)
    func enqueue(_ pkb: PacketBuffer) -> Bool
    func completeTx()

    var meta: IfaceMetadata { get set }
    func handle() -> IfaceHandle
}

public extension Iface {
    var description: String {
        return "\(name) -> \(meta.statistics)"
    }
}

public struct IfaceMetadata {
    public let property: IfaceProperty
    public var statistics: IfaceStatistics
    public let offload: IfaceOffload
    public let initialMac: MacAddress?
    public init(property: IfaceProperty, offload: IfaceOffload, initialMac: MacAddress?) {
        self.property = property
        statistics = IfaceStatistics()
        self.offload = offload
        self.initialMac = initialMac
    }
}

public struct IfaceProperty {
    public let layer: IfaceLayer
    public init(layer: IfaceLayer) {
        self.layer = layer
    }
}

public enum IfaceLayer {
    case ETHER
    case IP
}

public struct IfaceStatistics: Encodable, Decodable {
    public var rxbytes: UInt64 = 0
    public var rxpkts: UInt64 = 0
    public var rxerrcsum: UInt64 = 0

    public var txbytes: UInt64 = 0
    public var txpkts: UInt64 = 0
    public var txerr: UInt64 = 0

    public init() {}

    public mutating func inc(_ s: IfaceStatistics) {
        rxbytes += s.rxbytes
        rxpkts += s.rxpkts
        rxerrcsum += s.rxerrcsum
        txbytes += s.txbytes
        txpkts += s.txpkts
        txerr += s.txerr
    }
}

public struct IfaceOffload {
    public var rxcsum: CSumState
    public var txcsum: CSumState

    public init(rxcsum: CSumState, txcsum: CSumState) {
        self.rxcsum = rxcsum
        self.txcsum = txcsum
    }
}

public class IfaceHandle: Equatable, Hashable {
    public var iface: any Iface
    public init(iface: any Iface) {
        self.iface = iface
    }

    public func hash(into hasher: inout Hasher) {
        iface.hash(into: &hasher)
    }

    public static func == (lhs: IfaceHandle, rhs: IfaceHandle) -> Bool {
        return lhs === rhs
    }
}

open class VirtualIface: Iface {
    public var meta: IfaceMetadata
    open var name: String { "virtual" }
    private var ifaceInit_: IfaceInit? = nil
    public var ifaceInit: IfaceInit { ifaceInit_! }

    public init() {
        meta = IfaceMetadata(
            property: IfaceProperty(layer: .ETHER),
            offload: IfaceOffload(
                rxcsum: .UNNECESSARY,
                txcsum: .UNNECESSARY
            ),
            initialMac: nil
        )
    }

    public init(meta: IfaceMetadata) {
        self.meta = meta
    }

    open func initialize(_ ifaceInit: IfaceInit) throws(IOException) {
        ifaceInit_ = ifaceInit
    }

    open func close() {
        handle_ = nil
    }

    open func dequeue(_: inout [PacketBuffer], off _: inout Int) {
        // should be implemented in subclasses
    }

    open func enqueue(_: PacketBuffer) -> Bool {
        // should be implemented in subclasses
        return false
    }

    open func completeTx() {
        // should be implemented in subclasses
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

    open func hash(into hasher: inout Hasher) {
        HashHelper.hash(from: self, into: &hasher)
    }

    public static func == (lhs: VirtualIface, rhs: VirtualIface) -> Bool {
        return lhs.handle() == rhs.handle()
    }
}
