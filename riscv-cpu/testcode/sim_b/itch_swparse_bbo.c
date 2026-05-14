// Sim B path 1 (top-of-book) — software ITCH parse + best bid/ask tracking.
// Same packet bytes parsed each iteration; the BBO state machine updates
// best_bid / best_ask and conditionally increments buy_decisions when the
// spread tightens past SPREAD_THRESHOLD with sufficient shares.

#include <stdint.h>

#ifndef ITER
#define ITER 1000
#endif

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u
#define SPREAD_THRESHOLD 0x00001000u

volatile uint8_t packet[36] __attribute__((aligned(32))) = {
    0x41,
    0x12, 0x34,
    0x56, 0x78,
    0x00, 0x00, 0x00, 0xAB, 0xCD, 0xEF,
    0x00, 0x00, 0x00, 0x00, 0xDE, 0xAD, 0xBE, 0xEF,
    0x42,                                    // [19] side = 'B'
    0x00, 0x00, 0x03, 0xE8,
    'A', 'A', 'P', 'L', ' ', ' ', ' ', ' ',
    0x00, 0x01, 0x86, 0xA0,
};

volatile uint32_t best_bid       __attribute__((aligned(32))) = 0;
volatile uint32_t best_ask       = 0xFFFFFFFFu;
volatile uint32_t buy_decisions  = 0;

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    uint32_t bb = 0;
    uint32_t ba = 0xFFFFFFFFu;
    uint32_t bd = 0;

    for (int i = 0; i < ITER; i++) {
        uint32_t mtype  = (uint32_t)packet[0];
        uint32_t side   = (uint32_t)packet[19];
        uint32_t shares = ((uint32_t)packet[20] << 24) |
                          ((uint32_t)packet[21] << 16) |
                          ((uint32_t)packet[22] <<  8) |
                          ((uint32_t)packet[23] <<  0);
        uint32_t price  = ((uint32_t)packet[32] << 24) |
                          ((uint32_t)packet[33] << 16) |
                          ((uint32_t)packet[34] <<  8) |
                          ((uint32_t)packet[35] <<  0);

        if (mtype == 0x41u) {
            if (side == 0x42u) {
                if (price > bb) bb = price;
            } else if (side == 0x53u) {
                if (price < ba) ba = price;
            }
            if (ba > bb && (ba - bb) < SPREAD_THRESHOLD && shares > MIN_SHARES) {
                bd++;
            }
        }
    }

    best_bid      = bb;
    best_ask      = ba;
    buy_decisions = bd;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
