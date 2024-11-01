public class RingBuffer {
    private let buf: [UInt8]
    private var s = 0
    private var e = 0
    private var sIsAfterE = false

    public init(capacity: Int) {
        self.buf = Arrays.newArray(capacity: capacity, uninitialized: true)
    }

    public func storeFrom(_ f: ([UInt8], Int, Int) throws -> Int) rethrows -> Int {
        if freeSpace() == 0 {
            return 0
        }
        var n = 0
        if !sIsAfterE {
            let res = try f(buf, e, buf.capacity - e)
            if res < 0 {
                return res
            }
            if res == 0 {
                return 0
            }
            n += res
            e += res
            if e == buf.capacity {
                e = 0
                sIsAfterE = true
            }
            if freeSpace() == 0 {
                return n
            }
            if !sIsAfterE {
                // still has free space between e and cap
                // so all bytes had been read
                return n
            }
        }
        assert(sIsAfterE && freeSpace() > 0)
        let res = try f(buf, e, s - e)
        if res < 0 {
            if n > 0 {
                return n
            }
            return res
        }
        e += res
        return n + res
    }

    public func writeTo(_ f: ([UInt8], Int, Int) throws -> Int) rethrows -> Int {
        if usedSpace() == 0 {
            return 0
        }
        var n = 0
        if sIsAfterE {
            let res = try f(buf, s, buf.capacity - s)
            if res < 0 {
                return res
            }
            if res == 0 {
                return 0
            }
            n += res
            s += res
            if s == buf.capacity {
                s = 0
                sIsAfterE = false
            }
            if usedSpace() == 0 {
                reset()
                return n
            }
            if sIsAfterE {
                // still has data between s and cap
                // so data can't be written anymore
                return n
            }
        }
        assert(!sIsAfterE && usedSpace() > 0)

        let res = try f(buf, s, e - s)
        if res < 0 {
            if n > 0 {
                return n
            }
            return res
        }
        s += res
        if s == e {
            reset()
        }
        return res + n
    }

    private func reset() {
        s = 0
        e = 0
        sIsAfterE = false
    }

    public func freeSpace() -> Int {
        if sIsAfterE {
            return s - e
        } else {
            return buf.capacity - e + s
        }
    }

    public func usedSpace() -> Int {
        return buf.capacity - freeSpace()
    }
}
