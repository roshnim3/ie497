// Sim B path 3 (scaling) — custom-1 fetch_trade instruction. Loop body matches
// the single-shot version; ITER swept for the scaling study.

#include <stdint.h>

#ifndef ITER
#define ITER 100
#endif

#define FETCH_TRADE(field) ({                                          \
    uint32_t _r;                                                        \
    asm volatile (".insn i 0x2b, 0x0, %0, zero, " #field : "=r"(_r));   \
    _r;                                                                 \
})

volatile uint32_t decision __attribute__((aligned(32))) = 0;

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    uint32_t accum = 0;
    for (int i = 0; i < ITER; i++) {
        uint32_t mtype  = FETCH_TRADE(0);
        uint32_t shares = FETCH_TRADE(6);
        uint32_t price  = FETCH_TRADE(7);
        accum += (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    }
    decision = accum;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
