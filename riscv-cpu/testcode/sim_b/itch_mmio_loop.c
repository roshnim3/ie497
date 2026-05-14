// Sim B path 2 (scaling) — pre-parsed fields at fixed addresses; firmware does
// lw's, no byte-swap. Loop body matches the single-shot version.

#include <stdint.h>

#ifndef ITER
#define ITER 100
#endif

volatile uint32_t parsed_fields[8] __attribute__((aligned(32))) = {
    0x00000041,   // msg_type
    0x00000042,   // side = 'B'
    0x00ABCDEF,
    0x00000000,
    0xDEADBEEF,
    0x00000000,
    0x000003E8,
    0x000186A0,
};

volatile uint32_t decision __attribute__((aligned(32))) = 0;

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    uint32_t accum = 0;
    for (int i = 0; i < ITER; i++) {
        uint32_t mtype  = parsed_fields[0];
        uint32_t shares = parsed_fields[6];
        uint32_t price  = parsed_fields[7];
        accum += (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    }
    decision = accum;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
