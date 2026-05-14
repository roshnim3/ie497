// Sim B path 3 (top-of-book) — fetch_trade custom-1 instruction backs the 4
// field reads per iteration. BBO state machine identical to the other two
// paths; only the data-acquisition mechanism differs.

#include <stdint.h>

#ifndef ITER
#define ITER 1000
#endif

#define FETCH_TRADE(field) ({                                          \
    uint32_t _r;                                                        \
    asm volatile (".insn i 0x2b, 0x0, %0, zero, " #field : "=r"(_r));   \
    _r;                                                                 \
})

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u
#define SPREAD_THRESHOLD 0x00001000u

volatile uint32_t best_bid       __attribute__((aligned(32))) = 0;
volatile uint32_t best_ask       = 0xFFFFFFFFu;
volatile uint32_t buy_decisions  = 0;

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    uint32_t bb = 0;
    uint32_t ba = 0xFFFFFFFFu;
    uint32_t bd = 0;

    for (int i = 0; i < ITER; i++) {
        uint32_t mtype  = FETCH_TRADE(0);
        uint32_t side   = FETCH_TRADE(1);
        uint32_t shares = FETCH_TRADE(6);
        uint32_t price  = FETCH_TRADE(7);

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
