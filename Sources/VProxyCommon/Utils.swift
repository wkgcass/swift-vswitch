public class Utils {
    private init() {}

    public static func findNextPowerOf2(_ n: Int) -> Int {
        var n = n
        n -= 1
        n |= n >> 1
        n |= n >> 2
        n |= n >> 4
        n |= n >> 8
        n |= n >> 16
        return n + 1
    }
}
