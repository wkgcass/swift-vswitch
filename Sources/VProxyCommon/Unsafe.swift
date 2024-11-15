#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public class Unsafe {
    private init() {}

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
        let u8p: UnsafeMutablePointer<UInt8> = mut2mutUnsafe(p)
        return mut2mutUnsafe(u8p.advanced(by: inc))
    }

    @inlinable @inline(__always)
    public static func advance<T>(ptr p: UnsafePointer<T>, inc: Int) -> UnsafePointer<T> {
        let u8p: UnsafePointer<UInt8> = ptr2ptrUnsafe(p)
        return ptr2ptrUnsafe(u8p.advanced(by: inc))
    }

    @inlinable @inline(__always)
    public static func convertToNativeAddRef<T: AnyObject>(_ value: T) -> UnsafeMutableRawPointer {
        return Unmanaged<T>.passRetained(value).toOpaque()
    }

    @inlinable @inline(__always)
    public static func converToNativeKeepRef<T: AnyObject>(_ value: T) -> UnsafeMutableRawPointer {
        return Unmanaged<T>.passUnretained(value).toOpaque()
    }

    @inlinable @inline(__always)
    public static func convertFromNativeDecRef<T: AnyObject>(_ p: UnsafeRawPointer) -> T {
        return Unmanaged<T>.fromOpaque(p).takeRetainedValue()
    }

    @inlinable @inline(__always)
    public static func convertFromNativeKeepRef<T: AnyObject>(_ p: UnsafeRawPointer) -> T {
        return Unmanaged<T>.fromOpaque(p).takeUnretainedValue()
    }

    @inlinable @inline(__always)
    public static func releaseNativeRef(_ p: UnsafeRawPointer) {
        Unmanaged<AnyObject>.fromOpaque(p).release()
    }

    @inlinable @inline(__always)
    public static func malloc<T>() -> UnsafeMutablePointer<T>? {
#if canImport(Darwin)
        let p = Darwin.malloc(MemoryLayout<T>.stride)
#else
        let p = Glibc.malloc(MemoryLayout<T>.stride)
#endif
        guard let p else {
            return nil
        }
        return mutraw2mutptr(p)
    }

    @inlinable @inline(__always)
    public static func free<T>(_ p: UnsafePointer<T>?) {
        guard let p else {
            return
        }
#if canImport(Darwin)
        Darwin.free(ptr2mutraw(p))
#else
        Glibc.free(ptr2mutraw(p))
#endif
    }
}
