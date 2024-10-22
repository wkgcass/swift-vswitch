public class Convert {
    private init() {}

    public static func reverseByteOrder(_ n: UInt16) -> UInt16 {
        return ((n >> 8) & 0xFF) | ((n & 0xFF) << 8)
    }

    public static func raw2ptr<T>(_ raw: UnsafeRawPointer) -> UnsafePointer<T> {
        return raw.assumingMemoryBound(to: T.self)
    }

    public static func mutraw2ptr<T>(_ raw: UnsafeMutableRawPointer) -> UnsafePointer<T> {
        let p = raw.assumingMemoryBound(to: T.self)
        return UnsafePointer(p)
    }

    public static func mut2ptr<T>(_ p: UnsafeMutablePointer<T>) -> UnsafePointer<T> {
        return UnsafePointer(p)
    }

    public static func raw2mutptr<T>(_ raw: UnsafeRawPointer) -> UnsafeMutablePointer<T> {
        let p = raw.assumingMemoryBound(to: T.self)
        return UnsafeMutablePointer(mutating: p)
    }

    public static func mutraw2mutptr<T>(_ raw: UnsafeMutableRawPointer) -> UnsafeMutablePointer<T> {
        return raw.assumingMemoryBound(to: T.self)
    }

    public static func ptr2mutptr<T>(_ p: UnsafePointer<T>) -> UnsafeMutablePointer<T> {
        return UnsafeMutablePointer(mutating: p)
    }

    public static func ptr2raw<T>(_ p: UnsafePointer<T>) -> UnsafeRawPointer {
        return UnsafeRawPointer(p)
    }

    public static func mutptr2raw<T>(_ p: UnsafeMutablePointer<T>) -> UnsafeRawPointer {
        return UnsafeRawPointer(p)
    }

    public static func mutraw2raw(_ raw: UnsafeMutableRawPointer) -> UnsafeRawPointer {
        return UnsafeRawPointer(raw)
    }

    public static func ptr2mutraw<T>(_ p: UnsafePointer<T>) -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: p)
    }

    public static func mutptr2mutraw<T>(_ p: UnsafeMutablePointer<T>) -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: p)
    }

    public static func raw2mutraw(_ raw: UnsafeRawPointer) -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: raw)
    }

    public static func ptr2ptrUnsafe<T, U>(_ p: UnsafePointer<T>) -> UnsafePointer<U> {
        return raw2ptr(ptr2raw(p))
    }

    public static func mut2ptrUnsafe<T, U>(_ p: UnsafeMutablePointer<T>) -> UnsafePointer<U> {
        return mutraw2ptr(mutptr2mutraw(p))
    }

    public static func ptr2mutUnsafe<T, U>(_ p: UnsafePointer<T>) -> UnsafeMutablePointer<U> {
        return raw2mutptr(ptr2raw(p))
    }

    public static func mut2mutUnsafe<T, U>(_ p: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<U> {
        return mutraw2mutptr(mutptr2mutraw(p))
    }
}
