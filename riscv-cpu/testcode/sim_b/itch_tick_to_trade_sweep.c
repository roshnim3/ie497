// Sim B — tick-to-trade with packet-length sweep.
//
// Same workload as itch_tick_to_trade.c (poll parser, decide, emit on
// accept) but cycles the pkt_s length through {16, 32, 48, 64} octets per
// accepted iteration. The decision logic and 16-pkt_w buffer-fill are
// identical across all lengths — only the length operand passed to pkt_s
// changes. Expectation: TX drain segment scales linearly with len/4 (one
// AXI-Stream beat per 32b word), the other waterfall segments (rx_wait,
// decision, tx_issue) stay flat.
//
// Each accept's full waterfall lands in tick_to_trade_breakdown.csv;
// length per row can be recovered from tx_packets.csv (`length` column)
// or computed as LENGTHS[accept_idx & 3].
//
// Run:
//   make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" run_vcs_top_tb \
//        PROG=../testcode/sim_b/itch_tick_to_trade_sweep.c \
//        TIMEOUT=5000000 \
//        EXTRA_RUN_ARGS="+PARSER_ENABLE_ECE411=1 +PARSER_INTERVAL_ECE411=512"

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

// Same header words as itch_tick_to_trade.c — see that file for the
// per-byte layout. The frame is always built to 64 octets; pkt_s len just
// changes how many words the FSM drains.
#define HDR_W0   0x00000002u
#define HDR_W1   0x00020100u
#define HDR_W2   0x02000000u
#define HDR_W3   0x00450008u
#define HDR_W4   0x01003200u
#define HDR_W5   0x11400040u
#define HDR_W6   0x000A0000u
#define HDR_W7   0x000A0200u
#define HDR_W8   0xCDAB0100u
#define HDR_W9   0x1E003412u
#define HDR_W10  0x424F0000u
#define HDR_W14  0x59490000u
#define HDR_W15  0x00000000u

volatile uint32_t parsed_count   __attribute__((aligned(32))) = 0;
volatile uint32_t accept_count   __attribute__((aligned(32))) = 0;
volatile uint32_t reject_count   __attribute__((aligned(32))) = 0;
volatile uint32_t emitted_count  __attribute__((aligned(32))) = 0;

void main(void) {
    uint32_t accepts = 0;
    uint32_t rejects = 0;

    // Length cycle. Compile-time-constant array picked up via &3 below.
    static const uint32_t LENGTHS[4] = {16u, 32u, 48u, 64u};

    asm volatile ("slti x0, x0, 1" ::: "memory");

    // Drop preloaded slot (no PACKET_DONE, see itch_tick_to_trade.c).
    while (FETCH_TRADE(4)) {
    }
    (void)FETCH_TRADE(5);

    // Warmup iteration — emits a 64-octet frame to train BP / prime FU.
    {
        uint32_t mtype, side, seq, shares, price;
        while (FETCH_TRADE(4)) {
        }
        mtype  = FETCH_TRADE(0);
        side   = FETCH_TRADE(1);
        seq    = FETCH_TRADE(3);
        shares = FETCH_TRADE(6);
        price  = FETCH_TRADE(7);
        (void)side; (void)mtype;

        PKT_W(HDR_W0,   0);
        PKT_W(HDR_W1,   1);
        PKT_W(HDR_W2,   2);
        PKT_W(HDR_W3,   3);
        PKT_W(HDR_W4,   4);
        PKT_W(HDR_W5,   5);
        PKT_W(HDR_W6,   6);
        PKT_W(HDR_W7,   7);
        PKT_W(HDR_W8,   8);
        PKT_W(HDR_W9,   9);
        PKT_W(HDR_W10, 10);
        PKT_W(bswap32(seq),    11);
        PKT_W(bswap32(shares), 12);
        PKT_W(bswap32(price),  13);
        PKT_W(HDR_W14, 14);
        PKT_W(HDR_W15, 15);
        PKT_S(64u);

        (void)FETCH_TRADE(5);
        PACKET_DONE();
    }

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
            uint32_t len = LENGTHS[accepts & 0x3u];

            PKT_W(HDR_W0,   0);
            PKT_W(HDR_W1,   1);
            PKT_W(HDR_W2,   2);
            PKT_W(HDR_W3,   3);
            PKT_W(HDR_W4,   4);
            PKT_W(HDR_W5,   5);
            PKT_W(HDR_W6,   6);
            PKT_W(HDR_W7,   7);
            PKT_W(HDR_W8,   8);
            PKT_W(HDR_W9,   9);
            PKT_W(HDR_W10, 10);
            PKT_W(bswap32(seq),    11);
            PKT_W(bswap32(shares), 12);
            PKT_W(bswap32(price),  13);
            PKT_W(HDR_W14, 14);
            PKT_W(HDR_W15, 15);

            PKT_S(len);
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
    emitted_count = accepts;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
