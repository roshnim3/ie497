// Sim B path 1 — software ITCH 5.0 Add Order parse + trade decision.
// The packet sits in .data; firmware reads bytes, byte-swaps to little-endian,
// compares against threshold/min-shares, and writes the boolean decision.

#include <stdint.h>

// ITCH 5.0 Add Order Message (msg_type 'A' = 0x41), wire layout, 36 bytes,
// big-endian on the wire. Field offsets per NASDAQ TotalView-ITCH 5.0 spec:
//   [0]      msg_type
//   [1-2]    stock_locate
//   [3-4]    tracking_number
//   [5-10]   timestamp (6 bytes)
//   [11-18]  order_reference_number (8 bytes)
//   [19]     buy/sell indicator
//   [20-23]  shares
//   [24-31]  stock symbol (ASCII)
//   [32-35]  price (4-decimal fixed-point)
volatile uint8_t packet[36] __attribute__((aligned(32))) = {
    0x41,                                            // msg_type = 'A'
    0x12, 0x34,                                      // stock_locate
    0x56, 0x78,                                      // tracking_number
    0x00, 0x00, 0x00, 0xAB, 0xCD, 0xEF,              // timestamp
    0x00, 0x00, 0x00, 0x00, 0xDE, 0xAD, 0xBE, 0xEF,  // ref_num
    0x42,                                            // 'B' = buy
    0x00, 0x00, 0x03, 0xE8,                          // shares = 1000
    'A', 'A', 'P', 'L', ' ', ' ', ' ', ' ',          // symbol
    0x00, 0x01, 0x86, 0xA0,                          // price = 100000
};

volatile uint32_t decision __attribute__((aligned(32))) = 0;

#define PRICE_THRESHOLD  0x00010000u  // 65536, lower than the packet's 100000 -> trade
#define MIN_SHARES       100u

void main(void) {
    asm volatile ("slti x0, x0, 1" ::: "memory");

    uint32_t mtype = (uint32_t)packet[0];

    uint32_t shares = ((uint32_t)packet[20] << 24) |
                      ((uint32_t)packet[21] << 16) |
                      ((uint32_t)packet[22] <<  8) |
                      ((uint32_t)packet[23] <<  0);

    uint32_t price  = ((uint32_t)packet[32] << 24) |
                      ((uint32_t)packet[33] << 16) |
                      ((uint32_t)packet[34] <<  8) |
                      ((uint32_t)packet[35] <<  0);

    uint32_t d = (mtype == 0x41u) && (price > PRICE_THRESHOLD) && (shares > MIN_SHARES);
    decision = d;

    asm volatile ("slti x0, x0, 2" ::: "memory");
}
