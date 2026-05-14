// Sim B path 2 (top-of-book) — pre-parsed fields via MMIO loads, BBO state
// machine updates best bid / ask and counts decisions when spread tightens.

#include <stdint.h>

#ifndef ITER
#define ITER 1000
#endif

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u
#define SPREAD_THRESHOLD 0x00001000u

volatile uint32_t parsed_fields[8] __attribute__((aligned(32))) = {
    0x00000041,   // msg_type
    0x00000042,   // side = 'B'
    0x00ABCDEF,
    0x00000000,
    0xDEADBEEF,
    0x00000000,
    0x000003E8,   // shares
    0x000186A0,   // price
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
        uint32_t mtype  = parsed_fields[0];
        uint32_t side   = parsed_fields[1];
        uint32_t shares = parsed_fields[6];
        uint32_t price  = parsed_fields[7];

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
