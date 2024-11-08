import VProxyCommon

public class IfaceEx: CustomStringConvertible, Hashable {
    public let iface: any Iface

    public init(_ iface: any Iface, toBridge: UInt32) {
        self.iface = iface
        self.toBridge = toBridge
        mac = iface.meta.initialMac ?? MacAddress.random()
    }

    public init(_ iface: any Iface, toNetstack: UInt32) {
        self.iface = iface
        self.toNetstack = toNetstack
        mac = iface.meta.initialMac ?? MacAddress.random()
    }

    public var name: String { iface.name }

    public func initialize(_ ifaceInit: IfaceInit) throws(IOException) {
        try iface.initialize(ifaceInit)
    }

    public func close() {
        iface.close()
    }

    public func dequeue(_ packets: inout [PacketBuffer], off: inout Int) {
        iface.dequeue(&packets, off: &off)
    }

    public func enqueue(_ pkb: PacketBuffer) -> Bool {
        return iface.enqueue(pkb)
    }

    public func completeTx() {
        iface.completeTx()
    }

    public var meta: IfaceMetadata {
        get { iface.meta } set { iface.meta = newValue }
    }

    public func handle() -> IfaceHandle {
        iface.handle()
    }

    public var toBridge: UInt32 = 0
    public var toNetstack: UInt32 = 0
    public var mac: MacAddress

    public var description: String { iface.description }

    public func hash(into hasher: inout Hasher) {
        iface.hash(into: &hasher)
    }

    public static func == (lhs: IfaceEx, rhs: IfaceEx) -> Bool {
        return lhs.iface.handle() == rhs.iface.handle()
    }
}
