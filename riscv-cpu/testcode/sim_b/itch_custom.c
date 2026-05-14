// Sim B path 3 — custom-1 fetch_trade instruction. Each instruction reads a
// parsed field directly out of a dedicated BRAM-backed FU (XPM_MEMORY),
// bypassing the d-cache and memory hierarchy entirely.
//
// Encoding (I-type): opcode = 0x2b (custom-1), funct3 = 0,
//                    rs1 = x0, imm[2:0] = field index, rd = destination.

#include <stdint.h>

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

    uint32_t mtype  = FETCH_TRADE(0);   // msg_type
    uint32_t shares = FETCH_TRADE(6);   // shares
    uint32_t price  = FETCH_TRADE(7);   // price

    uint32_t d = (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    decision = d;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
