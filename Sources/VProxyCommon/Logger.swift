import VProxyCommonCHelper

public class Logger {
    private init() {}

    private static let DEBUG = "\u{001b}[0;36m"
    private static let TRACE = "\u{001b}[0;36m"
    private static let INFO = "\u{001b}[0;32m"
    private static let WARN = "\u{001b}[0;33m"
    private static let ERROR = "\u{001b}[0;31m"
    private static let RESET = "\u{001b}[0m"

    private static func currentTime() -> String {
        var buf: [CChar] = Arrays.newArray(capacity: 20)
        swvs_timefmt(&buf)
        return String(cString: &buf)
    }

    public static func lowLevelDebug(_ msg: String) -> Bool {
        print("\(DEBUG)[\(currentTime())][DEBUG] -\(RESET) \(msg)")
        return true
    }

    public static func error(_ logType: LogType, _ msg: String) {
        print("\(ERROR)[\(currentTime())][ERROR][\(logType)] -\(RESET) \(msg)")
    }

    public static func error(_ logType: LogType, _ msg: String, _ t: Error) {
        print("\(ERROR)[\(currentTime())][ERROR][\(logType)] -\(RESET) \(msg)")
        print(t)
    }

    public static func warn(_ logType: LogType, _ msg: String) {
        print("\(WARN)[\(currentTime())][WARN][\(logType)] -\(RESET) \(msg)")
    }

    public static func info(_ logType: LogType, _ msg: String) {
        print("\(INFO)[\(currentTime())][INFO][\(logType)] -\(RESET) \(msg)")
    }

    public static func trace(_ logType: LogType, _ msg: String) {
        print("\(TRACE)[\(currentTime())][TRACE][\(logType)] -\(RESET) \(msg)")
    }

    public static func alert(_ msg: String) {
        info(.ALERT, msg)
    }

    public static func shouldNotHappen(_ msg: String) {
        error(.SHOULD_NOT_HAPPEN, msg)
    }
}

public enum LogType {
    case ALERT
    case SOCKET_ERROR
    case SYS_ERROR
    case IMPROPER_USE
    case CONN_ERROR
    case SHOULD_NOT_HAPPEN
    case INVALID_INPUT_DATA
}
