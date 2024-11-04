public class Logger {
    private init() {}

    public static func lowLevelDebug(_ msg: String) -> Bool {
        print(msg)
        return true
    }

    public static func error(_: LogType, _ msg: String) {
        print(msg)
    }

    public static func error(_: LogType, _ msg: String, _ t: Error) {
        print(msg)
        print(t)
    }

    public static func warn(_: LogType, _ msg: String) {
        print(msg)
    }

    public static func info(_: LogType, _ msg: String) {
        print(msg)
    }

    public static func trace(_: LogType, _ msg: String) {
        print(msg)
    }

    public static func alert(_ msg: String) {
        info(.ALERT, msg)
    }
}

public enum LogType {
    case ALERT
    case SOCKET_ERROR
    case SYS_ERROR
    case IMPROPER_USE
    case CONN_ERROR
}
