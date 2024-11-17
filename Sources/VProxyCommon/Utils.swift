public class Utils {
    private init() {}

    @inlinable @inline(__always)
    public static func byteOrderConvert(_ n: UInt16) -> UInt16 {
        return ((n >> 8) & 0xff) | ((n & 0xff) << 8)
    }

    @inlinable @inline(__always)
    public static func hexCharToByte(_ c: CChar) -> UInt8 {
        if c >= 48 && c <= 57 {
            return UInt8(c) - 48
        } else if c >= 65 && c <= 70 {
            return UInt8(c) - 55
        } else if c >= 97 && c <= 102 {
            return UInt8(c) - 87
        } else { // should not reach here
            return 255
        }
    }

    @inlinable @inline(__always)
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

    @inlinable @inline(__always)
    public static func isPowerOf2(_ n: Int) -> Bool {
        return (n & (n - 1)) == 0
    }
}

public extension [UInt8] {
    @inlinable @inline(__always)
    static func fromHex(_ hexString: String) -> [UInt8]? {
        let utf8 = hexString.utf8CString
        if (utf8.count - 1) % 2 != 0 {
            return nil
        }
        let size = (utf8.count - 1) / 2
        var result: [UInt8] = Arrays.newArray(capacity: size, uninitialized: true)
        for i in 0 ..< size {
            let high = utf8[2 * i]
            let low = utf8[2 * i + 1]
            result[i] = (Utils.hexCharToByte(high) << 4) | Utils.hexCharToByte(low)
        }
        return result
    }
}

public class Box<T>: CustomStringConvertible {
    public var pointee: T
    public init(_ pointee: T) {
        self.pointee = pointee
    }

    public var description: String {
        return String(describing: pointee)
    }
}
