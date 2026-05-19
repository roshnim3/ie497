// Sim B — max-throughput benchmark.
//
// Emits M=100 fixed 64-octet frames as fast as the CPU + TX FU can run
// them. pkt_st is used to gate the producer:
//   - Before each pkt_w/pkt_s burst, spin on pkt_st(tx_full) so we only
//     enter the inner sequence when there's a free staging slot.
//   - After the inner loop, spin on pkt_st(tx_empty) to wait for the
//     drain FSM to flush the remaining backlog before we stop the timer.
//
// Start/end cycle stamps come from `slti x0, x0, 5` / `slti x0, x0, 6`
// markers — the testbench captures the cycle counts and dumps
// throughput.csv.
//
// Theoretical drain limit: 16 cycles per 64-octet frame (one AXI-Stream
// beat per word). cycles_per_packet <= 17 (drain + 1-cycle FSM gap)
// means the firmware is keeping the wire saturated.
//
// Run:
//   make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" run_vcs_top_tb \
//        PROG=../testcode/sim_b/itch_max_throughput.c TIMEOUT=5000000

#include <stdint.h>

#ifndef M_PACKETS
#define M_PACKETS 100
#endif

#define PKT_W(val, off) \
    asm volatile (".insn i 0x5b, 0x0, x0, %0, " #off : : "r"(val) : "memory")

#define PKT_S(len) \
    asm volatile (".insn i 0x5b, 0x1, x0, %0, 0" : : "r"(len) : "memory")

#define PKT_ST(field) ({                                              \
    uint32_t _r;                                                       \
    asm volatile (".insn i 0x5b, 0x2, %0, zero, " #field : "=r"(_r));  \
    _r;                                                                \
})

#define START_TIMER() asm volatile ("slti x0, x0, 5" ::: "memory")
#define STOP_TIMER()  asm volatile ("slti x0, x0, 6" ::: "memory")
#define HALT_END()    asm volatile ("slti x0, x0, 2" ::: "memory")

// Fixed 64-octet OUCH-style frame, same payload every iteration.
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
#define HDR_W11  0x01000000u   // token = 1 (big-endian)
#define HDR_W12  0xE8030000u   // qty   = 1000
#define HDR_W13  0xA0860100u   // price = 100000
#define HDR_W14  0x59490000u
#define HDR_W15  0x00000000u

volatile uint32_t bench_packets __attribute__((aligned(32))) = 0;

void main(void) {
    // Skip the FU's preloaded slot if any so the staging FIFO starts clean.
    // (Preloaded slot is on the fetch_trade FIFO, not the TX FIFO, so this
    // is purely defensive.)
    asm volatile ("slti x0, x0, 1" ::: "memory");

    // ---- Hot loop: keep the staging FIFO full. ----
    START_TIMER();

    for (uint32_t i = 0; i < M_PACKETS; i++) {
        // Gate on pkt_st(tx_full). pkt_st bypasses the RS's fifo_full
        // stall so this poll always succeeds; the body re-enters as
        // soon as a slot frees up.
        while (PKT_ST(1)) { }

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
        PKT_W(HDR_W11, 11);
        PKT_W(HDR_W12, 12);
        PKT_W(HDR_W13, 13);
        PKT_W(HDR_W14, 14);
        PKT_W(HDR_W15, 15);
        PKT_S(64u);
    }

    // Wait for the FSM to drain the remaining backlog before stopping
    // the timer — otherwise we'd under-measure the last few packets.
    while (!PKT_ST(0)) { }

    STOP_TIMER();

    bench_packets = M_PACKETS;

    HALT_END();
}
