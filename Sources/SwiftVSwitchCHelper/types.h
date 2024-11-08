#include <inttypes.h>

struct swvs_ethhdr {
    uint8_t     dst[6];
    uint8_t     src[6];
    uint16_t be_type;
} __attribute__((packed));

struct swvs_vlantag {
    uint16_t be_vid;
    uint16_t be_type;
} __attribute__((packed));

struct swvs_arp {
    uint16_t be_arp_hardware;
    uint16_t be_arp_protocol;
    uint8_t     arp_hlen;
    uint8_t     arp_plen;
    uint16_t be_arp_opcode;
    uint8_t     arp_sha[6];
    uint8_t     arp_sip[4];
    uint8_t     arp_tha[6];
    uint8_t     arp_tip[4];
} __attribute__((packed));

struct swvs_ipv4hdr {
    uint8_t     version_ihl;
    uint8_t     type_of_service;
    uint16_t be_total_length;
    uint16_t be_packet_id;
    uint16_t be_fragment_offset;
    uint8_t     time_to_live;
    uint8_t     proto;
    uint8_t     csum[2];
    uint8_t     src[4];
    uint8_t     dst[4];
} __attribute__((packed));

struct swvs_ipv6hdr {
    uint8_t     vtc_flow[4];
    uint16_t be_payload_len;
    uint8_t     next_hdr;
    uint8_t     hop_limits;
    uint8_t     src[16];
    uint8_t     dst[16];
} __attribute__((packed));

struct swvs_ipv6nxthdr {
    uint8_t next_hdr;
    uint8_t len;
} __attribute__((packed));

struct swvs_icmp_hdr {
    uint8_t type;
    uint8_t code;
    uint8_t csum[2];
} __attribute__((packed));

struct swvs_icmp_echo {
    uint16_t be_id;
    uint16_t be_seq;
} __attribute__((packed));

struct swvs_icmp_ns {
    uint8_t reserved[4];
    uint8_t target[16];
} __attribute__((packed));

struct swvs_icmp_na {
    uint8_t rso;
    uint8_t reserved[3];
    uint8_t target[16];
} __attribute__((packed));

struct swvs_icmp_ndp_opt {
    uint8_t type;
    uint8_t len;
} __attribute__((packed));

struct swvs_icmp_ndp_opt_link_layer_addr {
    uint8_t type;
    uint8_t len;
    uint8_t addr[6];
} __attribute__((packed));

struct swvs_tcphdr {
    uint16_t be_src_port;
    uint16_t be_dst_port;
    uint32_t be_sent_seq;
    uint32_t be_recv_ack;
    uint8_t     data_off;
    uint8_t     flags;
    uint16_t    win;
    uint8_t     csum[2];
    uint16_t    urp;
} __attribute__((packed));

struct swvs_udphdr {
    uint16_t be_src_port;
    uint16_t be_dst_port;
    uint16_t be_len;
    uint8_t     csum[2];
} __attribute__((packed));

// =========== composed ===========

struct swvs_compose_eth_arp {
    struct swvs_ethhdr ethhdr;
    struct swvs_arp    arp;
} __attribute__((packed));

struct swvs_compose_icmp_echoreq {
    struct swvs_icmp_hdr icmp;
    uint16_t          be_id;
    uint16_t          be_seq;
    char                 data[0];
} __attribute__((packed));

struct swvs_compose_icmpv6_ns {
    struct swvs_icmp_hdr icmp;
    uint32_t             reserved;
    uint8_t              target[16];
} __attribute__((packed));

struct swvs_compose_icmpv6_na_tlla {
    struct swvs_icmp_hdr icmp;
    uint8_t              flags;
    uint8_t              reserved0;
    uint16_t             reserved1;
    uint8_t              target[16];
    struct swvs_icmp_ndp_opt_link_layer_addr opt;
} __attribute__((packed));

struct swvs_compose_eth_ip6_icmp6_ns_slla {
    struct swvs_ethhdr   ethhdr;
    struct swvs_ipv6hdr  v6;
    struct swvs_icmp_hdr icmp;
    uint32_t             reserved;
    uint8_t              target[16];
    struct swvs_icmp_ndp_opt_link_layer_addr opt;
} __attribute__((packed));
