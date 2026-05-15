// Sim B — Phase 2 multi-buffer TX test.
//
// Sends three 64-byte packets back-to-back with distinct byte patterns.
// Each packet's first byte = 0x10 * (packet_idx+1), then ascending. So:
//   packet 0: 10 11 12 ... 4F   (first byte 0x10)
//   packet 1: 20 21 22 ... 5F   (first byte 0x20)
//   packet 2: 30 31 32 ... 6F   (first byte 0x30)
//
// The point of this test is to confirm:
//   1. Multiple packets queue and drain in order.
//   2. The CPU can pipeline pkt_w for packet K+1 while the HW is still
//      emitting packet K (RS doesn't stall except on FIFO-full).
//   3. Length is recorded per slot — each packet drains its own length.
//
// Run:
//   make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" run_vcs_top_tb \
//        PROG=../testcode/sim_b/itch_send_multi.c TIMEOUT=2000000

#include <stdint.h>

#define PKT_W(val, off) \
    asm volatile (".insn i 0x5b, 0x0, x0, %0, " #off : : "r"(val) : "memory")

#define PKT_S(len) \
    asm volatile (".insn i 0x5b, 0x1, x0, %0, 0" : : "r"(len) : "memory")

#define PACKET_DONE() asm volatile ("slti x0, x0, 7" ::: "memory")

static inline void fill_slot(uint32_t base) {
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
}

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    // base offsets: 0x10, 0x20, 0x30 added to every byte so packets are
    // distinguishable in the captured CSV. 0x10101010 added to each word.
    fill_slot(0x10101010u);
    PKT_S(64u);
    PACKET_DONE();

    fill_slot(0x20202020u);
    PKT_S(64u);
    PACKET_DONE();

    fill_slot(0x30303030u);
    PKT_S(64u);
    PACKET_DONE();

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
