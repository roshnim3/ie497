// Sim B — TX primitive smoke test.
//
// Builds a 64-byte ARP-style packet by issuing 16 pkt_w instructions to
// fill the TX BRAM, then triggers a send with pkt_s. The testbench's
// fake_packet_sink captures the emitted bytes to tx_packets.csv.
//
// Encoding (custom-2, opcode 0x5b):
//   pkt_w  funct3=0  ".insn i 0x5b, 0x0, rd, rs1, off"   — write rs1 (4B) to BRAM[off]
//   pkt_s  funct3=1  ".insn i 0x5b, 0x1, rd, rs1, 0"     — emit first rs1 bytes
// Both target rd=x0 (the writeback is just so the ROB can retire).
//
// Run:
//   make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" run_vcs_top_tb \
//        PROG=../testcode/sim_b/itch_send_packet.c \
//        TIMEOUT=2000000

#include <stdint.h>

#define PKT_W(val, off) \
    asm volatile (".insn i 0x5b, 0x0, x0, %0, " #off : : "r"(val) : "memory")

#define PKT_S(len) \
    asm volatile (".insn i 0x5b, 0x1, x0, %0, 0" : : "r"(len) : "memory")

#define PACKET_DONE() asm volatile ("slti x0, x0, 7" ::: "memory")

// 64-byte payload — 16 little-endian 32-bit words. The pattern is
// recognizable in the CSV: bytes 0x00..0x3F in ascending order.
//
//   word 0:  0x03020100   →   bytes  00 01 02 03
//   word 1:  0x07060504   →   bytes  04 05 06 07
//   ...
//   word 15: 0x3F3E3D3C   →   bytes  3C 3D 3E 3F

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    PKT_W(0x03020100u, 0);
    PKT_W(0x07060504u, 1);
    PKT_W(0x0B0A0908u, 2);
    PKT_W(0x0F0E0D0Cu, 3);
    PKT_W(0x13121110u, 4);
    PKT_W(0x17161514u, 5);
    PKT_W(0x1B1A1918u, 6);
    PKT_W(0x1F1E1D1Cu, 7);
    PKT_W(0x23222120u, 8);
    PKT_W(0x27262524u, 9);
    PKT_W(0x2B2A2928u, 10);
    PKT_W(0x2F2E2D2Cu, 11);
    PKT_W(0x33323130u, 12);
    PKT_W(0x37363534u, 13);
    PKT_W(0x3B3A3938u, 14);
    PKT_W(0x3F3E3D3Cu, 15);

    PKT_S(64u);

    PACKET_DONE();

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
