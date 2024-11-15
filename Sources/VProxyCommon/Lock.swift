#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct Lock {
    private var lock_ = pthread_mutex_t()

    public init() {
        pthread_mutex_init(&lock_, nil)
    }

    public mutating func lock() {
        pthread_mutex_lock(&lock_)
    }

    public mutating func unlock() {
        pthread_mutex_unlock(&lock_)
    }
}

public struct RWLock {
    private var lock_ = pthread_rwlock_t()

    public init() {
        pthread_rwlock_init(&lock_, nil)
    }

    public mutating func rlock() {
        pthread_rwlock_rdlock(&lock_)
    }

    public mutating func wlock() {
        pthread_rwlock_wrlock(&lock_)
    }

    public mutating func unlock() {
        pthread_rwlock_unlock(&lock_)
    }
}

public class LockRef {
    private var lock_ = Lock()
    public init() {}

    public func lock() {
        lock_.lock()
    }

    public func unlock() {
        lock_.unlock()
    }
}

public class RWLockRef {
    private var lock_ = RWLock()
    public init() {}

    public func rlock() {
        lock_.rlock()
    }

    public func wlock() {
        lock_.wlock()
    }

    public func unlock() {
        lock_.unlock()
    }
}
