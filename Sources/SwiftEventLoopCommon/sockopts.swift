public class SockOpts {
    public static let SO_RCVBUF: SocketOption<Int> = SocketOption(name: SocketOptionName.SO_RCVBUF)
    public static let SO_BROADCAST: SocketOption<Bool> = SocketOption(name: SocketOptionName.SO_BROADCAST)
    public static let SO_LINGER: SocketOption<Int> = SocketOption(name: SocketOptionName.SO_LINGER)
    public static let SO_REUSEPORT: SocketOption<Bool> = SocketOption(name: SocketOptionName.SO_REUSEPORT)
    public static let TCP_NODELAY: SocketOption<Bool> = SocketOption(name: SocketOptionName.TCP_NODELAY)
    public static let IP_TRANSPARENT: SocketOption<Bool> = SocketOption(name: SocketOptionName.IP_TRANSPARENT)
}

public final class SocketOptionName: CustomStringConvertible, Sendable {
    let name: String
    public init(_ name: String) {
        self.name = name
    }

    public var description: String {
        return name
    }

    static let SO_RCVBUF = SocketOptionName("SO_RECVBUF")
    static let SO_BROADCAST = SocketOptionName("SO_BROADCAST")
    static let SO_LINGER = SocketOptionName("SO_LINGER")
    static let SO_REUSEPORT = SocketOptionName("SO_REUSEPORT")
    static let TCP_NODELAY = SocketOptionName("TCP_NODELAY")
    static let IP_TRANSPARENT = SocketOptionName("IP_TRANSPARENT")
}

public struct SocketOption<T>: CustomStringConvertible, Sendable, Equatable {
    private let name: SocketOptionName
    public init(name: SocketOptionName) {
        self.name = name
    }

    public var description: String {
        return name.description
    }

    public static func == (lhs: SocketOption<T>, rhs: SocketOption<T>) -> Bool {
        return lhs.name === rhs.name
    }
}
