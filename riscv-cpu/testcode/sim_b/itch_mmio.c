// Sim B path 2 — pre-parsed ITCH fields live as 32-bit, little-endian words at
// fixed addresses (simulating a hardware parser that has populated a BRAM that
// the CPU sees as memory-mapped). Firmware does plain lw's, no byte-swap, then
// makes the same trade decision as path 1.

#include <stdint.h>

// "Hardware parser" output. Pre-loaded by the link / memory image with the
// values that would result from parsing the same Add Order packet used in
// itch_swparse.c. Layout:
//   [0] msg_type       (only low byte meaningful)
//   [1] stock_locate
//   [2] timestamp_lo   (low 32 bits)
//   [3] timestamp_hi   (high 16 bits of 48-bit field)
//   [4] ref_num_lo
//   [5] ref_num_hi
//   [6] shares
//   [7] price
volatile uint32_t parsed_fields[8] __attribute__((aligned(32))) = {
    0x00000041,   // msg_type
    0x00001234,   // stock_locate
    0x00ABCDEF,   // timestamp_lo
    0x00000000,   // timestamp_hi
    0xDEADBEEF,   // ref_num_lo
    0x00000000,   // ref_num_hi
    0x000003E8,   // shares  = 1000
    0x000186A0,   // price   = 100000
};

volatile uint32_t decision __attribute__((aligned(32))) = 0;

#define PRICE_THRESHOLD  0x00010000u
#define MIN_SHARES       100u

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    uint32_t mtype  = parsed_fields[0];
    uint32_t shares = parsed_fields[6];
    uint32_t price  = parsed_fields[7];

    uint32_t d = (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    decision = d;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
