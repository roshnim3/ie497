// Sim B path 2 (mixed) — MMIO loads + concurrent independent ALU work.
// ALU block is identical to itch_swparse_mixed.c; only the data acquisition
// differs.

#include <stdint.h>

#ifndef ITER
#define ITER 1000
#endif

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u

volatile uint32_t parsed_fields[8] __attribute__((aligned(32))) = {
    0x00000041,
    0x00000042,
    0x00ABCDEF,
    0x00000000,
    0xDEADBEEF,
    0x00000000,
    0x000003E8,
    0x000186A0,
};

volatile uint32_t decision __attribute__((aligned(32))) = 0;
volatile uint32_t acc_out                                = 0;

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    uint32_t acc  = 0;
    uint32_t dcnt = 0;

    for (int i = 0; i < ITER; i++) {
        uint32_t x = (uint32_t)i;
        acc += x * 3u;
        acc ^= x << 5;
        acc -= x * 7u;
        acc += x >> 2;

        uint32_t mtype  = parsed_fields[0];
        uint32_t shares = parsed_fields[6];
        uint32_t price  = parsed_fields[7];
        dcnt += (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    }
    decision = dcnt;
    acc_out  = acc;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
