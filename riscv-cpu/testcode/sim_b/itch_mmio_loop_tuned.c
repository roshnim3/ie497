// Sim B path 2 (hand-tuned) — same workload as itch_mmio_loop.c but the
// three loads are emitted via inline assembly with a single shared base
// register and immediate offsets, eliminating any address-arithmetic
// overhead the compiler might emit. This is the "what would an HFT shop
// actually write?" version of the MMIO path, used to plug the credible
// critique that compiler-generated lw sequences leave performance on the
// table. If fetch_trade still beats this, the speedup claim is honest.

#include <stdint.h>

#ifndef ITER
#define ITER 1000
#endif

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

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    const uint32_t base = (uint32_t)parsed_fields;
    uint32_t accum = 0;

    for (int i = 0; i < ITER; i++) {
        uint32_t mtype, shares, price;
        // Force three back-to-back lws from one base + immediate offsets.
        // No address arithmetic per iteration; LSQ pipelines the loads.
        asm volatile (
            "lw %0,  0(%3)\n"     // parsed_fields[0]  = msg_type
            "lw %1, 24(%3)\n"     // parsed_fields[6]  = shares
            "lw %2, 28(%3)\n"     // parsed_fields[7]  = price
            : "=r"(mtype), "=r"(shares), "=r"(price)
            : "r"(base)
            : "memory"
        );
        accum += (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    }

    decision = accum;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
