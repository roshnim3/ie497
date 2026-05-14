// Sim B (streaming) — poll the fetch_trade BRAM's seq slot, process each
// new packet driven by the behavioral parser, and emit a per-packet
// completion marker the testbench uses to timestamp commits for the
// latency histogram.
//
// Run with the testbench in streaming mode:
//   make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" run_vcs_top_tb \
//        PROG=../testcode/sim_b/itch_stream.c \
//        TIMEOUT=20000000 \
//        EXTRA_RUN_ARGS="+PARSER_ENABLE_ECE411=1 +PARSER_INTERVAL_ECE411=32"

#include <stdint.h>

#ifndef N_PACKETS
#define N_PACKETS 100
#endif

#define FETCH_TRADE(field) ({                                          \
    uint32_t _r;                                                        \
    asm volatile (".insn i 0x2b, 0x0, %0, zero, " #field : "=r"(_r));   \
    _r;                                                                 \
})

// Per-packet completion marker. `slti x0, x0, 7` is an inert ALU op
// (writes to x0) that the testbench detects in the commit stream to
// timestamp packet completion for the latency histogram.
#define PACKET_DONE() asm volatile ("slti x0, x0, 7" ::: "memory")

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u

volatile uint32_t decision __attribute__((aligned(32))) = 0;

void main(void) {
    uint32_t last_seq  = 0;
    uint32_t decisions = 0;

    asm volatile ("slti x0, x0, 1" ::: "memory");

    for (uint32_t i = 0; i < N_PACKETS; i++) {
        // Poll the sequence slot until the parser publishes a new packet.
        uint32_t seq;
        do {
            seq = FETCH_TRADE(3);
        } while (seq == last_seq);
        last_seq = seq;

        // Read the fields the parser wrote for this packet.
        uint32_t mtype  = FETCH_TRADE(0);
        uint32_t side   = FETCH_TRADE(1);
        uint32_t shares = FETCH_TRADE(6);
        uint32_t price  = FETCH_TRADE(7);
        (void)side;  // unused in trivial decision

        if ((mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES)) {
            decisions++;
        }

        PACKET_DONE();
    }

    decision = decisions;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
