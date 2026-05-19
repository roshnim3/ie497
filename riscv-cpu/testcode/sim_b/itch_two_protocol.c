// Sim B — two-protocol demo.
//
// Phase 1: emit a single ARP request frame at startup (broadcast,
//          who-has 10.0.0.1 tell 10.0.0.2).
// Phase 2: identical to itch_tick_to_trade.c — poll parser, decide,
//          build OUCH order frames, send. Stop after consuming N
//          parser packets.
//
// Both phases use the SAME pkt_w/pkt_s primitives. Only the byte content
// of the buffer changes between an ARP and an OUCH frame.
//
// Run:
//   make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" run_vcs_top_tb \
//        PROG=../testcode/sim_b/itch_two_protocol.c \
//        TIMEOUT=5000000 \
//        EXTRA_RUN_ARGS="+PARSER_ENABLE_ECE411=1 +PARSER_INTERVAL_ECE411=512"
//   python3 script/decode_two_protocol.py sim/vcs/tx_packets.csv

#include <stdint.h>

#ifndef N_PACKETS
#define N_PACKETS 100
#endif

#define THRESHOLD_PRICE 99000u
#define MIN_SHARES      800u

#define FETCH_TRADE(field) ({                                          \
    uint32_t _r;                                                        \
    asm volatile (".insn i 0x2b, 0x0, %0, zero, " #field : "=r"(_r));   \
    _r;                                                                 \
})

#define PKT_W(val, off) \
    asm volatile (".insn i 0x5b, 0x0, x0, %0, " #off : : "r"(val) : "memory")

#define PKT_S(len) \
    asm volatile (".insn i 0x5b, 0x1, x0, %0, 0" : : "r"(len) : "memory")

#define PACKET_DONE() asm volatile ("slti x0, x0, 7" ::: "memory")

static inline uint32_t bswap32(uint32_t x) {
    return ((x & 0x000000FFu) << 24) |
           ((x & 0x0000FF00u) <<  8) |
           ((x & 0x00FF0000u) >>  8) |
           ((x & 0xFF000000u) >> 24);
}

// ----- ARP request (64 octets, bytes 42..63 are padding) -----
// Eth dst (broadcast): FF FF FF FF FF FF
// Eth src (us)       : 02 00 00 00 00 02
// Ethertype          : 08 06
// HTYPE / PTYPE      : 00 01 / 08 00
// HLEN / PLEN        : 06 / 04
// OPER               : 00 01  (request)
// Sender HW          : 02 00 00 00 00 02
// Sender Proto IP    : 0A 00 00 02  (10.0.0.2)
// Target HW          : 00 00 00 00 00 00  (unknown)
// Target Proto IP    : 0A 00 00 01  (10.0.0.1)
// Padding (22B)      : 00 ...
#define ARP_W0   0xFFFFFFFFu   // bytes  0- 3:  FF FF FF FF
#define ARP_W1   0x0002FFFFu   // bytes  4- 7:  FF FF 02 00
#define ARP_W2   0x02000000u   // bytes  8-11:  00 00 00 02
#define ARP_W3   0x01000608u   // bytes 12-15:  08 06 00 01
#define ARP_W4   0x04060008u   // bytes 16-19:  08 00 06 04
#define ARP_W5   0x00020100u   // bytes 20-23:  00 01 02 00
#define ARP_W6   0x02000000u   // bytes 24-27:  00 00 00 02
#define ARP_W7   0x0200000Au   // bytes 28-31:  0A 00 00 02
#define ARP_W8   0x00000000u   // bytes 32-35:  00 00 00 00
#define ARP_W9   0x000A0000u   // bytes 36-39:  00 00 0A 00
#define ARP_W10  0x00000100u   // bytes 40-43:  00 01 00 00
#define ARP_W11  0x00000000u   // bytes 44-47: padding
#define ARP_W12  0x00000000u   // bytes 48-51: padding
#define ARP_W13  0x00000000u   // bytes 52-55: padding
#define ARP_W14  0x00000000u   // bytes 56-59: padding
#define ARP_W15  0x00000000u   // bytes 60-63: padding

// ----- OUCH-over-UDP header constants (identical to itch_tick_to_trade.c) -----
#define OUCH_W0   0x00000002u
#define OUCH_W1   0x00020100u
#define OUCH_W2   0x02000000u
#define OUCH_W3   0x00450008u
#define OUCH_W4   0x01003200u
#define OUCH_W5   0x11400040u
#define OUCH_W6   0x000A0000u
#define OUCH_W7   0x000A0200u
#define OUCH_W8   0xCDAB0100u
#define OUCH_W9   0x1E003412u
#define OUCH_W10  0x424F0000u
#define OUCH_W14  0x59490000u
#define OUCH_W15  0x00000000u

volatile uint32_t parsed_count   __attribute__((aligned(32))) = 0;
volatile uint32_t accept_count   __attribute__((aligned(32))) = 0;
volatile uint32_t reject_count   __attribute__((aligned(32))) = 0;
volatile uint32_t emitted_count  __attribute__((aligned(32))) = 0;

void main(void) {
    uint32_t accepts = 0;
    uint32_t rejects = 0;

    asm volatile ("slti x0, x0, 1" ::: "memory");

    // ----- Phase 1: ARP request. Same pkt_w/pkt_s sequence as OUCH;
    //                only the byte payload changes. -----
    PKT_W(ARP_W0,   0);
    PKT_W(ARP_W1,   1);
    PKT_W(ARP_W2,   2);
    PKT_W(ARP_W3,   3);
    PKT_W(ARP_W4,   4);
    PKT_W(ARP_W5,   5);
    PKT_W(ARP_W6,   6);
    PKT_W(ARP_W7,   7);
    PKT_W(ARP_W8,   8);
    PKT_W(ARP_W9,   9);
    PKT_W(ARP_W10, 10);
    PKT_W(ARP_W11, 11);
    PKT_W(ARP_W12, 12);
    PKT_W(ARP_W13, 13);
    PKT_W(ARP_W14, 14);
    PKT_W(ARP_W15, 15);
    PKT_S(64u);

    // ----- Phase 2: order emission (mirrors itch_tick_to_trade.c). -----

    // Drop the FU's preloaded slot.
    while (FETCH_TRADE(4)) {
    }
    (void)FETCH_TRADE(5);

    for (uint32_t i = 0; i < N_PACKETS; i++) {
        while (FETCH_TRADE(4)) {
        }

        uint32_t mtype  = FETCH_TRADE(0);
        uint32_t side   = FETCH_TRADE(1);
        uint32_t seq    = FETCH_TRADE(3);
        uint32_t shares = FETCH_TRADE(6);
        uint32_t price  = FETCH_TRADE(7);
        (void)side;

        uint32_t accept = (mtype == 0x41u)
                       && (price  >  THRESHOLD_PRICE)
                       && (shares >= MIN_SHARES);

        if (accept) {
            PKT_W(OUCH_W0,   0);
            PKT_W(OUCH_W1,   1);
            PKT_W(OUCH_W2,   2);
            PKT_W(OUCH_W3,   3);
            PKT_W(OUCH_W4,   4);
            PKT_W(OUCH_W5,   5);
            PKT_W(OUCH_W6,   6);
            PKT_W(OUCH_W7,   7);
            PKT_W(OUCH_W8,   8);
            PKT_W(OUCH_W9,   9);
            PKT_W(OUCH_W10, 10);
            PKT_W(bswap32(seq),    11);
            PKT_W(bswap32(shares), 12);
            PKT_W(bswap32(price),  13);
            PKT_W(OUCH_W14, 14);
            PKT_W(OUCH_W15, 15);
            PKT_S(64u);
            accepts++;
        } else {
            rejects++;
        }

        (void)FETCH_TRADE(5);
        PACKET_DONE();
    }

    parsed_count  = N_PACKETS;
    accept_count  = accepts;
    reject_count  = rejects;
    emitted_count = accepts + 1;   // +1 for the ARP frame

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
