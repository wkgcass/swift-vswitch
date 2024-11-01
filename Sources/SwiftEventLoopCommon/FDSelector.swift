import VProxyCommon

public protocol FDSelector: AnyObject {
    func isOpen() -> Bool
    func select(_ entries: inout [SelectedEntry]) throws(IOException) -> Int
    func selectNow(_ entries: inout [SelectedEntry]) throws(IOException) -> Int
    func select(_ entries: inout [SelectedEntry], millis: Int) throws(IOException) -> Int
    func wakeup()
    func isRegistered(_ fd: any FD) -> Bool
    func register(_ fd: any FD, ops: EventSet, attachment: UnsafeMutableRawPointer?) throws(IOException)
    func remove(_ fd: any FD) -> UnsafeMutableRawPointer?
    func modify(_ fd: any FD, ops: EventSet)
    func events(_ fd: any FD) -> EventSet
    func attachment(_ fd: any FD) -> UnsafeMutableRawPointer?
    func entries() -> [RegisterEntry]
    func close()
    func getFiredExtra() -> (Int, UnsafePointer<FiredExtra>)
}

public struct SelectedEntry {
    private var fd_: (any FD)?
    public var fd: any FD { fd_! }
    public let ready: EventSet
    public let attachment: UnsafeMutableRawPointer?
    public init(fd: any FD, ready: EventSet, attachment: UnsafeMutableRawPointer?) {
        fd_ = fd
        self.ready = ready
        self.attachment = attachment
    }
}

public struct EventSet: Equatable, Sendable, CustomStringConvertible {
    private let e1: Event?
    private let e2: Event?

    private init() {
        e1 = nil
        e2 = nil
    }

    private init(_ e: Event) {
        e1 = e
        e2 = nil
    }

    private init(_ e1: Event, _ e2: Event) {
        assert(e1 != e2)
        if e1 == Event.READABLE {
            self.e1 = e1
            self.e2 = e2
        } else {
            self.e1 = e2
            self.e2 = e1
        }
    }

    public func have(_ e: Event) -> Bool {
        return e1 == e || e2 == e
    }

    public func combine(_ set: EventSet) -> EventSet {
        if self == set {
            // combine the same set
            return self
        }

        if e2 != nil {
            // all events set, no need to modify
            return self
        }

        if e1 == nil {
            // no event set, return the input set instead
            return set
        }

        // combine different events
        if set.e1 == Event.READABLE {
            if have(Event.WRITABLE) {
                return .readwrite()
            }
        }
        if set.e1 == Event.WRITABLE {
            if have(Event.READABLE) {
                return .readwrite()
            }
        }

        // otherwise they are the same
        return self
    }

    public func reduce(_ set: EventSet) -> EventSet {
        if self == set {
            // reduce the same set
            return .none()
        }

        if e1 == nil {
            // no event in this set, no need to modify
            return self
        }

        if set.e1 == nil {
            // no event in the input set, no need to modify
            return self
        }

        // reduce found events
        if set.e2 != nil {
            return .none()
        } else if set.have(Event.READABLE) {
            if have(Event.READABLE) {
                return .write()
            }
        } else if set.have(Event.WRITABLE) {
            // set have WRITABLE
            if have(Event.WRITABLE) {
                return .read()
            }
        }

        // otherwise no operations required
        return self
    }

    public var description: String {
        if e1 == nil {
            return "N"
        } else if e2 != nil {
            return "\(e1!)\(e2!)"
        } else {
            return "\(e1!)"
        }
    }

    private static let NONE = EventSet()
    private static let READ = EventSet(.READABLE)
    private static let WRITE = EventSet(.WRITABLE)
    private static let BOTH = EventSet(.READABLE, .WRITABLE)

    public static func none() -> EventSet {
        return NONE
    }

    public static func read() -> EventSet {
        return READ
    }

    public static func write() -> EventSet {
        return WRITE
    }

    public static func readwrite() -> EventSet {
        return BOTH
    }
}

public enum Event: Sendable, CustomStringConvertible {
    case READABLE
    case WRITABLE

    public var description: String {
        return switch self {
        case .READABLE: "R"
        case .WRITABLE: "W"
        }
    }
}

public struct RegisterEntry {
    public let fd: any FD
    public internal(set) var eventSet: EventSet
    public internal(set) var attachment: UnsafeMutableRawPointer?

    public init(fd: any FD, eventSet: EventSet, attachment: UnsafeMutableRawPointer?) {
        self.fd = fd
        self.eventSet = eventSet
        self.attachment = attachment
    }
}

public struct FiredExtra {
    public var ud: UnsafeRawPointer
    public var mask: Int32
    private var _padding: Int32
}
