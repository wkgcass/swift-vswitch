import SwiftEventLoopCommon
import VProxyCommon

public protocol Iface: AnyObject, CustomStringConvertible, Hashable {
    var name: String { get }
    func initialize(_ ifaceInit: IfaceInit) throws(IOException)
    func close() // don't forget to release the handle pointer

    func dequeue(_ packets: inout [PacketBuffer], off: inout Int)
    func enqueue(_ pkb: PacketBuffer) -> Bool
    func completeTx()

    var property: IfaceProperty { get }
    var statistics: IfaceStatistics { get set }
    var offload: IfaceOffload { get }
    func handle() -> IfaceHandle
}

public extension Iface {
    var description: String {
        return "\(name) -> \(statistics)"
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

public struct IfaceStatistics {
    public var rxbytes: UInt64
    public var rxpkts: UInt64
    public var rxerrcsum: UInt64

    public var txbytes: UInt64
    public var txpkts: UInt64
    public var txerr: UInt64

    public init() {
        rxbytes = 0
        rxpkts = 0
        rxerrcsum = 0
        txbytes = 0
        txpkts = 0
        txerr = 0
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

public class VirtualIface: Iface {
    public var statistics: IfaceStatistics
    public private(set) var offload: IfaceOffload
    open var name: String { "virtual" }
    private var ifaceInit_: IfaceInit? = nil
    public var ifaceInit: IfaceInit { ifaceInit_! }
    open var property: IfaceProperty { IfaceProperty(layer: .ETHER) }

    public init() {
        statistics = IfaceStatistics()
        offload = IfaceOffload(
            rxcsum: .UNNECESSARY,
            txcsum: .UNNECESSARY
        )
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
