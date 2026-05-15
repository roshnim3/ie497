// Sim B — Phase 2 deliberate overlap test.
//
// Pumps 8 distinct 64-byte packets back-to-back with no PACKET_DONE marker
// between them, so the CPU stays in the pkt_w/pkt_s issue stream without
// branches. The FU's staging FIFO holds 8 slots; when the CPU runs ahead
// of the drain FSM, it starts pre-filling slot K+1 while the FSM is still
// emitting slot K, which forces simultaneous Port A writes (pkt_w) and
// Port B reads (FSM emit). The top_tb's pkt_tx_overlap_cycles counter
// records every cycle that overlap happens — must be > 0 to prove the
// dual-port BRAM is genuinely serving both sides concurrently.
//
// Each packet's byte pattern is offset by 0x10 * packet_idx so the
// captured CSV rows are unambiguous.

#include <stdint.h>

#define PKT_W(val, off) \
    asm volatile (".insn i 0x5b, 0x0, x0, %0, " #off : : "r"(val) : "memory")

#define PKT_S(len) \
    asm volatile (".insn i 0x5b, 0x1, x0, %0, 0" : : "r"(len) : "memory")

static inline __attribute__((always_inline)) void fill_and_send(uint32_t base) {
    PKT_W(base + 0x03020100u, 0);
    PKT_W(base + 0x07060504u, 1);
    PKT_W(base + 0x0B0A0908u, 2);
    PKT_W(base + 0x0F0E0D0Cu, 3);
    PKT_W(base + 0x13121110u, 4);
    PKT_W(base + 0x17161514u, 5);
    PKT_W(base + 0x1B1A1918u, 6);
    PKT_W(base + 0x1F1E1D1Cu, 7);
    PKT_W(base + 0x23222120u, 8);
    PKT_W(base + 0x27262524u, 9);
    PKT_W(base + 0x2B2A2928u, 10);
    PKT_W(base + 0x2F2E2D2Cu, 11);
    PKT_W(base + 0x33323130u, 12);
    PKT_W(base + 0x37363534u, 13);
    PKT_W(base + 0x3B3A3938u, 14);
    PKT_W(base + 0x3F3E3D3Cu, 15);
    PKT_S(64u);
}

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    fill_and_send(0x10101010u);
    fill_and_send(0x20202020u);
    fill_and_send(0x30303030u);
    fill_and_send(0x40404040u);
    fill_and_send(0x50505050u);
    fill_and_send(0x60606060u);
    fill_and_send(0x70707070u);
    fill_and_send(0x80808080u);

    asm volatile ("slti x0, x0, 7" ::: "memory");   // one PACKET_DONE at the end
    asm volatile ("slti x0, x0, 2" ::: "memory");
}
