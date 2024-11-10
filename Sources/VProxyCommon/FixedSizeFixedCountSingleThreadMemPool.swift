#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public class FixedSizeFixedCountSingleThreadMemPool {
    public let size: Int
    public let count: Int
    private var buf: UnsafeMutablePointer<UInt8>
    private var chunks: [Chunk]
    private var off = 0

    public init?(size: Int, count: Int) {
        self.size = size
        self.count = count
        let ptr = malloc(size * count)
        guard let ptr else {
            return nil
        }
        buf = Convert.mutraw2mutptr(ptr)
        chunks = Arrays.newArray(capacity: count)
        for i in 0 ..< count {
            chunks[i].index = i
        }
    }

    public func get() -> (Int, UnsafeMutablePointer<UInt8>)? {
        let oldOff = off
        while true {
            let c = chunks[off]
            off += 1
            if off == count {
                off = 0
            }
            if c.used {
                if oldOff == off {
                    return nil
                }
                continue
            }
            chunks[c.index].used = true
            return (c.index, buf.advanced(by: c.index * size))
        }
    }

    public func store(_ i: Int) {
        chunks[i].used = false
    }

    public struct Chunk {
        var used: Bool
        var index: Int
    }
}
