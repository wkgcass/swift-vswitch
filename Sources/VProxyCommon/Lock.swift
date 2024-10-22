#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct Lock {
    private let lock_: [pthread_mutex_t] = Arrays.newArray(capacity: 1)
    private let pointer: UnsafeMutablePointer<pthread_mutex_t>

    public init() {
        pointer = Convert.ptr2mutUnsafe(Arrays.getRaw(from: lock_))
        pthread_mutex_init(pointer, nil)
    }

    public func lock() {
        pthread_mutex_lock(pointer)
    }

    public func unlock() {
        pthread_mutex_unlock(pointer)
    }
}
