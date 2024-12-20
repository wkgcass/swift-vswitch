import Collections
import VProxyCommon

public let ETHER_TYPE_8021Q: UInt16 = 0x8100
public let ETHER_TYPE_ARP: UInt16 = 0x0806
public let ETHER_TYPE_IPv4: UInt16 = 0x0800
public let ETHER_TYPE_IPv6: UInt16 = 0x86dd

public let BE_ETHER_TYPE_8021Q = Utils.byteOrderConvert(ETHER_TYPE_8021Q)
public let BE_ETHER_TYPE_ARP = Utils.byteOrderConvert(ETHER_TYPE_ARP)
public let BE_ETHER_TYPE_IPv4 = Utils.byteOrderConvert(ETHER_TYPE_IPv4)
public let BE_ETHER_TYPE_IPv6 = Utils.byteOrderConvert(ETHER_TYPE_IPv6)

public let ARP_PROTOCOL_TYPE_IP: UInt16 = 0x0800
public let ARP_HARDWARE_TYPE_ETHER: UInt16 = 1
public let ARP_PROTOCOL_OPCODE_REQ: UInt16 = 1
public let ARP_PROTOCOL_OPCODE_RESP: UInt16 = 2

public let BE_ARP_PROTOCOL_TYPE_IP = Utils.byteOrderConvert(ARP_PROTOCOL_TYPE_IP)
public let BE_ARP_HARDWARE_TYPE_ETHER = Utils.byteOrderConvert(ARP_HARDWARE_TYPE_ETHER)
public let BE_ARP_PROTOCOL_OPCODE_REQ = Utils.byteOrderConvert(ARP_PROTOCOL_OPCODE_REQ)
public let BE_ARP_PROTOCOL_OPCODE_RESP = Utils.byteOrderConvert(ARP_PROTOCOL_OPCODE_RESP)

public let IP_PROTOCOL_ICMP: UInt8 = 1
public let IP_PROTOCOL_ICMPv6: UInt8 = 58
public let IP_PROTOCOL_TCP: UInt8 = 6
public let IP_PROTOCOL_UDP: UInt8 = 17

public let IPv6_needs_next_header: Set<UInt8> = [0, 60, 43, 44, 51, 50, 135, 139, 140, 253, 254]

public let ICMP_PROTOCOL_TYPE_ECHO_REQ: UInt8 = 8
public let ICMPv6_PROTOCOL_TYPE_ECHO_REQ: UInt8 = 128
public let ICMP_PROTOCOL_TYPE_ECHO_RESP: UInt8 = 0
public let ICMPv6_PROTOCOL_TYPE_ECHO_RESP: UInt8 = 129
public let ICMP_PROTOCOL_TYPE_TIME_EXCEEDED: UInt8 = 11
public let ICMPv6_PROTOCOL_TYPE_TIME_EXCEEDED: UInt8 = 3
public let ICMPv6_PROTOCOL_TYPE_Neighbor_Solicitation: UInt8 = 135
public let ICMPv6_PROTOCOL_TYPE_Neighbor_Advertisement: UInt8 = 136
public let ICMPv6_OPTION_TYPE_Source_Link_Layer_Address: UInt8 = 1
public let ICMPv6_OPTION_TYPE_Target_Link_Layer_Address: UInt8 = 2
public let ICMP_PROTOCOL_TYPE_DEST_UNREACHABLE: UInt8 = 3
public let ICMP_PROTOCOL_CODE_PORT_UNREACHABLE: UInt8 = 3
public let ICMPv6_PROTOCOL_TYPE_DEST_UNREACHABLE: UInt8 = 1
public let ICMPv6_PROTOCOL_CODE_PORT_UNREACHABLE: UInt8 = 4

public let TCP_FLAGS_URG: UInt8 = 0b100000
public let TCP_FLAGS_ACK: UInt8 = 0b010000
public let TCP_FLAGS_PSH: UInt8 = 0b001000
public let TCP_FLAGS_RST: UInt8 = 0b000100
public let TCP_FLAGS_SYN: UInt8 = 0b000010
public let TCP_FLAGS_FIN: UInt8 = 0b000001

public nonisolated(unsafe) let IPv6_LINK_LOCAL_ADDRS = NetworkV6(from: "fe80::/10")!
public nonisolated(unsafe) let IPv6_Solicitation_Node_Multicast_Address = GetIP(from: "ff02::1:ff00:0")!
