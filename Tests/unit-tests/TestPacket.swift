import SwiftVSwitch
import Testing
import VProxyCommon

class TestPacket {
    @Test func tcp() {
        let packet = "7400000000013e0000000002080045000028890000004006b1edc0a802662486584eca2701bb02b5c544d5c12654501007ffd8000000"
        let bytes = Convert.toBytes(fromhex: packet)!
        let pkb = PacketBuffer(packetArray: bytes, offset: 0, pktlen: bytes.count, headroom: 0, tailroom: 0)
        #expect(pkb.description == "PacketBuffer(head=0,pkt=54,tail=0,dl_dst=74:00:00:00:00:01,dl_src=3e:00:00:00:00:02,dl_type=ip(2048),nw_src=192.168.2.102,nw_dst=36.134.88.78,nw_proto=tcp(6),tp_src=51751,tp_dst=443,app=0)")
        #expect(pkb.pktlen == bytes.count)
    }

    @Test func udp() {
        let packet = "7400000000013e0000000002080045000045000040004011cd3bc0a8026611f89866c44101bb003140696e19aa39dd01bb3a5dc9147241110bb6a94c07aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let bytes = Convert.toBytes(fromhex: packet)!
        let pkb = PacketBuffer(packetArray: bytes, offset: 0, pktlen: bytes.count, headroom: 0, tailroom: 0)
        #expect(pkb.description == "PacketBuffer(head=0,pkt=83,tail=0,dl_dst=74:00:00:00:00:01,dl_src=3e:00:00:00:00:02,dl_type=ip(2048),nw_src=192.168.2.102,nw_dst=17.248.152.102,nw_proto=udp(17),tp_src=50241,tp_dst=443,app=41)")
        #expect(pkb.pktlen == bytes.count)
    }

    @Test func icmp() {
        let packet = "7400000000013e0000000002080045000054378700004001ccdfc0a802666ef244420800a33c688a000067259bb0000afe5508090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f3031323334353637"
        let bytes = Convert.toBytes(fromhex: packet)!
        let pkb = PacketBuffer(packetArray: bytes, offset: 0, pktlen: bytes.count, headroom: 0, tailroom: 0)
        #expect(pkb.description == "PacketBuffer(head=0,pkt=98,tail=0,dl_dst=74:00:00:00:00:01,dl_src=3e:00:00:00:00:02,dl_type=ip(2048),nw_src=192.168.2.102,nw_dst=110.242.68.66,nw_proto=icmp(1),icmp_type=8,icmp_code=0,app=60)")
        #expect(pkb.pktlen == bytes.count)
    }

    @Test func ipv6NS() {
        let packet = "4c00000000013e000000000286dd6000000000203afffe8000000000000018b79d18e02d4970fe800000000000000c7b54fccc9110d28700e63300000000fe800000000000000c7b54fccc9110d201013ee65c369dac"
        let bytes = Convert.toBytes(fromhex: packet)!
        let pkb = PacketBuffer(packetArray: bytes, offset: 0, pktlen: bytes.count, headroom: 0, tailroom: 0)
        #expect(pkb.description == "PacketBuffer(head=0,pkt=86,tail=0,dl_dst=4c:00:00:00:00:01,dl_src=3e:00:00:00:00:02,dl_type=ipv6(34525),nw_src=fe80::18b7:9d18:e02d:4970,nw_dst=fe80::c7b:54fc:cc91:10d2,nw_proto=icmp6(58),icmp_type=135,icmp_code=0,app=28)")
        #expect(pkb.pktlen == bytes.count)
    }

    @Test func arp() {
        let packet = "3e0000000001e0000000000208060001080006040001e00000000001c0a802683e0000000002c0a80266000000000000000000000000000000000000"
        let bytes = Convert.toBytes(fromhex: packet)!
        #expect(bytes.count == 60)
        let pkb = PacketBuffer(packetArray: bytes, offset: 0, pktlen: bytes.count, headroom: 0, tailroom: 0)
        #expect(pkb.pktlen == 42)
        #expect(pkb.description == "PacketBuffer(head=0,pkt=42,tail=18,dl_dst=3e:00:00:00:00:01,dl_src=e0:00:00:00:00:02,dl_type=arp(2054),arp_spa=192.168.2.104,arp_tpa=192.168.2.102,proto=0,app=0)")
    }

    @Test func vlan() {
        let packet = "001562643341001c582364c18100000a080045000064f9a80000ff0185d0141414010a0a0a01000073770005188a000000000147f8fcabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcdabcd"
        let bytes = Convert.toBytes(fromhex: packet)!
        let pkb = PacketBuffer(packetArray: bytes, offset: 0, pktlen: bytes.count, headroom: 0, tailroom: 0)
        #expect(pkb.description == "PacketBuffer(head=0,pkt=118,tail=0,dl_dst=00:15:62:64:33:41,dl_src=00:1c:58:23:64:c1,vlan=10,dl_type=ip(2048),nw_src=20.20.20.1,nw_dst=10.10.10.1,nw_proto=icmp(1),icmp_type=0,icmp_code=0,app=76)")
        #expect(pkb.pktlen == bytes.count)
    }

    @Test func ipv6NextHeader() {
        let packet = "33330000001600123f97920186dd6000000000240001fe800000000000009c09b4160768ff42ff0200000000000000000000000000163a000502000001008f001a3c0000000103000000ff020000000000000000000000010003"
        let bytes = Convert.toBytes(fromhex: packet)!
        let pkb = PacketBuffer(packetArray: bytes, offset: 0, pktlen: bytes.count, headroom: 0, tailroom: 0)
        #expect(pkb.description == "PacketBuffer(head=0,pkt=90,tail=0,dl_dst=33:33:00:00:00:16,dl_src=00:12:3f:97:92:01,dl_type=ipv6(34525),nw_src=fe80::9c09:b416:768:ff42,nw_dst=ff02::16,nw_proto=icmp6(58),icmp_type=143,icmp_code=0,app=24)")
        #expect(pkb.pktlen == bytes.count)
    }
}
