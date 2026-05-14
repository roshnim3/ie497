// Sim B path 3 (mixed) — fetch_trade + concurrent independent ALU work.
// ALU block identical to the other two mixed firmwares. This is the
// stress test for the dedicated-FU design choice: if fetch_trade contended
// with the ALU lane, per-event cost would balloon here.

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

        uint32_t mtype  = FETCH_TRADE(0);
        uint32_t shares = FETCH_TRADE(6);
        uint32_t price  = FETCH_TRADE(7);
        dcnt += (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    }
    decision = dcnt;
    acc_out  = acc;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
