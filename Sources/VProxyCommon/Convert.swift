public class Convert {
    private init() {}

    @inlinable @inline(__always)
    public static func reverseByteOrder(_ n: UInt16) -> UInt16 {
        return ((n >> 8) & 0xFF) | ((n & 0xFF) << 8)
    }

    @inline(__always)
    private static func hexCharToByte(_ c: CChar) -> UInt8 {
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

    public static func toBytes(fromhex hexString: String) -> [UInt8]? {
        let utf8 = hexString.utf8CString
        if (utf8.count - 1) % 2 != 0 {
            return nil
        }
        let size = (utf8.count - 1) / 2
        var result: [UInt8] = Arrays.newArray(capacity: size, uninitialized: true)
        for i in 0 ..< size {
            let high = utf8[2 * i]
            let low = utf8[2 * i + 1]
            result[i] = (hexCharToByte(high) << 4) | hexCharToByte(low)
        }
        return result
    }

    @inlinable @inline(__always)
    public static func raw2ptr<T>(_ raw: UnsafeRawPointer) -> UnsafePointer<T> {
        return raw.assumingMemoryBound(to: T.self)
    }

    @inlinable @inline(__always)
    public static func mutraw2ptr<T>(_ raw: UnsafeMutableRawPointer) -> UnsafePointer<T> {
        let p = raw.assumingMemoryBound(to: T.self)
        return UnsafePointer(p)
    }

    @inlinable @inline(__always)
    public static func mut2ptr<T>(_ p: UnsafeMutablePointer<T>) -> UnsafePointer<T> {
        return UnsafePointer(p)
    }

    @inlinable @inline(__always)
    public static func raw2mutptr<T>(_ raw: UnsafeRawPointer) -> UnsafeMutablePointer<T> {
        let p = raw.assumingMemoryBound(to: T.self)
        return UnsafeMutablePointer(mutating: p)
    }

    @inlinable @inline(__always)
    public static func mutraw2mutptr<T>(_ raw: UnsafeMutableRawPointer) -> UnsafeMutablePointer<T> {
        return raw.assumingMemoryBound(to: T.self)
    }

    @inlinable @inline(__always)
    public static func ptr2mutptr<T>(_ p: UnsafePointer<T>) -> UnsafeMutablePointer<T> {
        return UnsafeMutablePointer(mutating: p)
    }

    @inlinable @inline(__always)
    public static func ptr2raw<T>(_ p: UnsafePointer<T>) -> UnsafeRawPointer {
        return UnsafeRawPointer(p)
    }

    @inlinable @inline(__always)
    public static func mutptr2raw<T>(_ p: UnsafeMutablePointer<T>) -> UnsafeRawPointer {
        return UnsafeRawPointer(p)
    }

    @inlinable @inline(__always)
    public static func mutraw2raw(_ raw: UnsafeMutableRawPointer) -> UnsafeRawPointer {
        return UnsafeRawPointer(raw)
    }

    @inlinable @inline(__always)
    public static func ptr2mutraw<T>(_ p: UnsafePointer<T>) -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: p)
    }

    @inlinable @inline(__always)
    public static func mutptr2mutraw<T>(_ p: UnsafeMutablePointer<T>) -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: p)
    }

    @inlinable @inline(__always)
    public static func raw2mutraw(_ raw: UnsafeRawPointer) -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: raw)
    }

    @inlinable @inline(__always)
    public static func ptr2ptrUnsafe<T, U>(_ p: UnsafePointer<T>) -> UnsafePointer<U> {
        return raw2ptr(ptr2raw(p))
    }

    @inlinable @inline(__always)
    public static func mut2ptrUnsafe<T, U>(_ p: UnsafeMutablePointer<T>) -> UnsafePointer<U> {
        return mutraw2ptr(mutptr2mutraw(p))
    }

    @inlinable @inline(__always)
    public static func ptr2mutUnsafe<T, U>(_ p: UnsafePointer<T>) -> UnsafeMutablePointer<U> {
        return raw2mutptr(ptr2raw(p))
    }

    @inlinable @inline(__always)
    public static func mut2mutUnsafe<T, U>(_ p: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<U> {
        return mutraw2mutptr(mutptr2mutraw(p))
    }

    @inlinable @inline(__always)
    public static func advance<T>(mut p: UnsafeMutablePointer<T>, inc: Int) -> UnsafeMutablePointer<T> {
        let u8p: UnsafeMutablePointer<UInt8> = Convert.mut2mutUnsafe(p)
        return Convert.mut2mutUnsafe(u8p.advanced(by: inc))
    }

    @inlinable @inline(__always)
    public static func advance<T>(ptr p: UnsafePointer<T>, inc: Int) -> UnsafePointer<T> {
        let u8p: UnsafePointer<UInt8> = Convert.ptr2ptrUnsafe(p)
        return Convert.ptr2ptrUnsafe(u8p.advanced(by: inc))
    }
}
