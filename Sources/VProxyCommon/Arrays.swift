#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public class Arrays {
    private init() {}

    public static func newArray<T>(capacity: Int, uninitialized: Bool = false) -> [T] {
        return [T](unsafeUninitializedCapacity: capacity, initializingWith: { p, c in
            if !uninitialized {
                memset(Convert.mutptr2mutraw(p.baseAddress!), 0, MemoryLayout<T>.stride * capacity)
            }
            c = capacity
        })
    }

    public static func getRaw<T>(from array: borrowing [T], offset: Int = 0) -> UnsafeMutablePointer<T> {
        return array.withUnsafeBufferPointer { bp in Convert.ptr2mutptr(bp.baseAddress!) }.advanced(by: offset)
    }
}
