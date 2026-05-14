// Sim B path 1 (mixed) — software parse + concurrent independent ALU work.
// Each iteration does ~4 ALU ops on a running accumulator before doing the
// parse + decide. The ALU work is independent of the parse result; OoO
// should overlap them. Compare per-event cycles to itch_swparse_loop.c to
// see how much the extra ALU work costs.

#include <stdint.h>

#ifndef ITER
#define ITER 1000
#endif

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u

volatile uint8_t packet[36] __attribute__((aligned(32))) = {
    0x41,
    0x12, 0x34,
    0x56, 0x78,
    0x00, 0x00, 0x00, 0xAB, 0xCD, 0xEF,
    0x00, 0x00, 0x00, 0x00, 0xDE, 0xAD, 0xBE, 0xEF,
    0x42,
    0x00, 0x00, 0x03, 0xE8,
    'A', 'A', 'P', 'L', ' ', ' ', ' ', ' ',
    0x00, 0x01, 0x86, 0xA0,
};

volatile uint32_t decision __attribute__((aligned(32))) = 0;
volatile uint32_t acc_out                                = 0;

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    uint32_t acc   = 0;
    uint32_t dcnt  = 0;

    for (int i = 0; i < ITER; i++) {
        // Independent ALU work (mimics running stats / hash maintenance)
        uint32_t x = (uint32_t)i;
        acc += x * 3u;
        acc ^= x << 5;
        acc -= x * 7u;
        acc += x >> 2;

        // Parse + decide
        uint32_t mtype = (uint32_t)packet[0];
        uint32_t shares = ((uint32_t)packet[20] << 24) |
                          ((uint32_t)packet[21] << 16) |
                          ((uint32_t)packet[22] <<  8) |
                          ((uint32_t)packet[23] <<  0);
        uint32_t price  = ((uint32_t)packet[32] << 24) |
                          ((uint32_t)packet[33] << 16) |
                          ((uint32_t)packet[34] <<  8) |
                          ((uint32_t)packet[35] <<  0);
        dcnt += (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    }
    decision = dcnt;
    acc_out  = acc;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
