import VProxyCommon

public class IfaceEx: CustomStringConvertible, Hashable {
    public var id: UInt32
    public let iface: any Iface

    public convenience init(_ id: UInt32, _ iface: any Iface, toBridge: UInt32) {
        self.init(id, iface, params: IfaceExParams(), toBridge: toBridge)
    }

    public init(_ id: UInt32, _ iface: any Iface, params: IfaceExParams, toBridge: UInt32) {
        self.id = id
        self.iface = iface
        self.toBridge = toBridge
        mac = iface.meta.initialMac ?? params.mac
    }

    public init(_ id: UInt32, _ iface: any Iface, params: IfaceExParams, toNetstack: UInt32) {
        self.id = id
        self.iface = iface
        self.toNetstack = toNetstack
        mac = iface.meta.initialMac ?? params.mac
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

public struct IfaceExParams {
    public var mac: MacAddress
    public init(mac: MacAddress) {
        self.mac = mac
    }

    public init() {
        mac = MacAddress.random()
    }
}

public protocol IfacePerThreadProvider {
    mutating func provide(tid: Int) throws(IOException) -> (any Iface)?
}

public struct SingleThreadIfaceProvider: IfacePerThreadProvider {
    public var iface: any Iface
    public init(iface: any Iface) {
        self.iface = iface
    }

    public func provide(tid: Int) -> (any Iface)? {
        if tid == 1 {
            return iface
        }
        return nil
    }
}

public struct PrototypeIfaceProvider: IfacePerThreadProvider {
    public let supplier: () throws(IOException) -> any Iface
    public init(supplier: @escaping () throws(IOException) -> any Iface) {
        self.supplier = supplier
    }

    public func provide(tid _: Int) throws(IOException) -> (any Iface)? {
        return try supplier()
    }
}

public class DummyIface: Iface {
    public var name: String
    public var meta: IfaceMetadata

    init(name: String, meta: IfaceMetadata) {
        self.name = name
        self.meta = meta
    }

    public func initialize(_: IfaceInit) throws(VProxyCommon.IOException) {}

    public func close() {
        handle_ = nil
    }

    public func dequeue(_: inout [PacketBuffer], off _: inout Int) {}

    public func enqueue(_: PacketBuffer) -> Bool { false }

    public func completeTx() {}

    private var handle_: IfaceHandle? = nil
    public func handle() -> IfaceHandle {
        if handle_ == nil {
            handle_ = IfaceHandle(iface: self)
        }
        return handle_!
    }

    public func hash(into hasher: inout Hasher) {
        ObjectIdentifier(self).hash(into: &hasher)
    }

    public static func == (lhs: DummyIface, rhs: DummyIface) -> Bool {
        return lhs === rhs
    }
}
