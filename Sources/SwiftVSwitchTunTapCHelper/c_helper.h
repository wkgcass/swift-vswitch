#include <inttypes.h>

struct swvs_tap_info {
    char dev_name[16];
    int  fd;
};

int swvs_open_tap(const char* dev_chars, uint8_t is_tun, struct swvs_tap_info* ret);

struct virtio_net_hdr_v1 {
#define VIRTIO_NET_HDR_F_NEEDS_CSUM  1    /* Use csum_start, csum_offset */
#define VIRTIO_NET_HDR_F_DATA_VALID  2    /* Csum is valid */
    uint8_t  flags;
#define VIRTIO_NET_HDR_GSO_NONE      0    /* Not a GSO frame */
#define VIRTIO_NET_HDR_GSO_TCPV4     1    /* GSO frame, IPv4 TCP (TSO) */
#define VIRTIO_NET_HDR_GSO_UDP       3    /* GSO frame, IPv4 UDP (UFO) */
#define VIRTIO_NET_HDR_GSO_TCPV6     4    /* GSO frame, IPv6 TCP */
#define VIRTIO_NET_HDR_GSO_UDP_L4    5    /* GSO frame, IPv4& IPv6 UDP (USO) */
#define VIRTIO_NET_HDR_GSO_ECN       0x80 /* TCP has ECN set */
    uint8_t  gso_type;
    uint16_t hdr_len;     /* Ethernet + IP + tcp/udp hdrs */
    uint16_t gso_size;    /* Bytes to append to hdr_len per frame */
    uint16_t csum_start;
    uint16_t csum_offset;
    uint16_t num_buffers;
} __attribute__((packed));
