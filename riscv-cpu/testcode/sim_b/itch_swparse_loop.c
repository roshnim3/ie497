// Sim B path 1 (scaling) — software ITCH 5.0 parse + trade decision, run ITER
// times in a loop. Same packet, same fields, same comparisons as the
// single-shot version. ITER is the swept parameter for the scaling study.

#include <stdint.h>

#ifndef ITER
#define ITER 100
#endif

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

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    uint32_t accum = 0;
    for (int i = 0; i < ITER; i++) {
        uint32_t mtype = (uint32_t)packet[0];
        uint32_t shares = ((uint32_t)packet[20] << 24) |
                          ((uint32_t)packet[21] << 16) |
                          ((uint32_t)packet[22] <<  8) |
                          ((uint32_t)packet[23] <<  0);
        uint32_t price  = ((uint32_t)packet[32] << 24) |
                          ((uint32_t)packet[33] << 16) |
                          ((uint32_t)packet[34] <<  8) |
                          ((uint32_t)packet[35] <<  0);
        accum += (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    }
    decision = accum;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
