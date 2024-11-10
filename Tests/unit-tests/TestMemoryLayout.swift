import VProxyCommon
import Testing

class TestMemoryLayout {
    @Test func pktTuple() {
        let size = MemoryLayout<PktTuple>.size
        let stride = MemoryLayout<PktTuple>.stride
        #expect(size == 104)
        #expect(stride == 104)
        var off = MemoryLayout<PktTuple>.offset(of: \.srcIp)
        #expect(off == 8)
        off = MemoryLayout<PktTuple>.offset(of: \.dstIp)
        #expect(off == 48)
        off = MemoryLayout<PktTuple>.offset(of: \.ud64)
        #expect(off == 88)
    }
}
