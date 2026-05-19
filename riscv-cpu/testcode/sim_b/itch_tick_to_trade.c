// Sim B — tick-to-trade closed loop.
//
// Streams 100 ITCH-like trades from the behavioral parser, runs the
// decision (mtype=='A' && price>THRESHOLD_PRICE && shares>=MIN_SHARES),
// and on accept builds a 64-octet Ethernet/IPv4/UDP/OUCH frame in the TX
// BRAM and triggers pkt_s. On reject the firmware just pops and moves on.
//
// Tracked end-to-end paths:
//   parser BRAM commit  -->  fetch_trade FU read  -->  decision branch
//     -->  16 pkt_w + pkt_s(64)  -->  AXI-Stream first beat at the sink.
// Testbench timestamps parser_commit and first AXI-Stream beat per
// accepted packet and writes tick_to_trade_latency.csv.
//
// The fetch_trade FU comes up with packet 0 preloaded (MEMORY_INIT_PARAM,
// seq=1) before the parser writes its first packet (seq=2 onward). The
// preloaded slot has no parser_commit pulse, so we drop it before the
// metric loop — that keeps every PACKET_DONE the testbench sees aligned
// with the parser packet whose write_ts[] entry produced it.
//
// Frame layout (64 octets, network byte order):
//   bytes 00..05  Ethernet dst MAC  02:00:00:00:00:01
//   bytes 06..11  Ethernet src MAC  02:00:00:00:00:02
//   bytes 12..13  Ethertype         0x0800 (IPv4)
//   bytes 14..33  IPv4 header       proto=17, src=10.0.0.2, dst=10.0.0.1
//   bytes 34..41  UDP header        src=0xABCD, dst=0x1234, len=30
//   bytes 42..63  OUCH-style body   msg='O' side='B' token qty price
//                                   locate TIF='I' display='Y' pad
//
// Run:
//   make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" run_vcs_top_tb \
//        PROG=../testcode/sim_b/itch_tick_to_trade.c \
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

// RISC-V base ISA has no native bswap. Used to swap rs1-native little-
// endian values into the network byte order the OUCH body expects.
static inline uint32_t bswap32(uint32_t x) {
    return ((x & 0x000000FFu) << 24) |
           ((x & 0x0000FF00u) <<  8) |
           ((x & 0x00FF0000u) >>  8) |
           ((x & 0xFF000000u) >> 24);
}

// Pre-computed constant header words. Names follow the BRAM word offset.
// Each constant encodes 4 octets in transmission order packed LSB-first
// (PKT_W's payload becomes bytes [7:0]=octet0, [15:8]=octet1, ...).
//
// On-wire bytes  =>  constant value
// Word  0: 02 00 00 00          -> 0x00000002
// Word  1: 00 01 02 00          -> 0x00020100
// Word  2: 00 00 00 02          -> 0x02000000
// Word  3: 08 00 45 00          -> 0x00450008
// Word  4: 00 32 00 01          -> 0x01003200
// Word  5: 40 00 40 11          -> 0x11400040
// Word  6: 00 00 0A 00          -> 0x000A0000
// Word  7: 00 02 0A 00          -> 0x000A0200
// Word  8: 00 01 AB CD          -> 0xCDAB0100
// Word  9: 12 34 00 1E          -> 0x1E003412
// Word 10: 00 00 'O' 'B'        -> 0x424F0000  (0x42='B', 0x4F='O')
// Word 14: 00 00 'I' 'Y'        -> 0x59490000  (0x49='I', 0x59='Y')
// Word 15: 00 00 00 00          -> 0x00000000
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

// Tohost-style counters readable from the simulation memory dump or by
// peeking the d-cache state. The testbench also computes parsed / emitted
// independently from write_idx and tx_idx so these are mostly for sanity.
volatile uint32_t parsed_count   __attribute__((aligned(32))) = 0;
volatile uint32_t accept_count   __attribute__((aligned(32))) = 0;
volatile uint32_t reject_count   __attribute__((aligned(32))) = 0;
volatile uint32_t emitted_count  __attribute__((aligned(32))) = 0;

void main(void) {
    uint32_t accepts = 0;
    uint32_t rejects = 0;

    asm volatile ("slti x0, x0, 1" ::: "memory");

    // Drop the preloaded slot (MEMORY_INIT_PARAM packet, no parser
    // commit). Do NOT emit PACKET_DONE here — keeps the testbench's
    // PACKET_DONE count aligned with parser-committed packets.
    while (FETCH_TRADE(4)) {
    }
    (void)FETCH_TRADE(5);

    for (uint32_t i = 0; i < N_PACKETS; i++) {
        // Spin while the FIFO is empty (slot 4 returns 1 if empty).
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

            // OUCH body — multi-byte fields are network byte order.
            PKT_W(bswap32(seq),    11);   // order token
            PKT_W(bswap32(shares), 12);   // quantity
            PKT_W(bswap32(price),  13);   // price

            PKT_W(HDR_W14, 14);
            PKT_W(HDR_W15, 15);

            PKT_S(64u);
            accepts++;
        } else {
            rejects++;
        }

        // Pop the head packet (advance FIFO tail).
        (void)FETCH_TRADE(5);

        PACKET_DONE();
    }

    parsed_count  = N_PACKETS;
    accept_count  = accepts;
    reject_count  = rejects;
    emitted_count = accepts;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
