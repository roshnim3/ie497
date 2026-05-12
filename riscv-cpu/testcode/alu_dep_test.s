.section .text
.globl _start

# ALU-only dependency stress test (no branches/loads/stores)
# - Chains of RAW dependencies
# - Mix of I-type and R-type
# - Same-dest overwrite (WAW) patterns

_start:
    # Seed a few registers
    addi x1,  x0, 1           # x1 = 1
    addi x2,  x0, 2           # x2 = 2
    addi x3,  x0, -3          # x3 = -3
    addi x4,  x0, 0x10        # x4 = 16 (use as shift amount source later)
    
    # Long single-register dependency chain on x5
    addi x5,  x1,  7          # x5 = 1 + 7 = 8
    slli x5,  x5,  2          # x5 = 8 << 2 = 32
    xori x5,  x5,  0x55       # x5 ^= 0x55
    andi x5,  x5,  0xFF       # keep low byte only
    srli x5,  x5,  3          # logical right shift
    ori  x5,  x5,  0x3        # set low bits
    srai x5,  x5,  1          # arithmetic right shift

    # Cross-register RAW chain: x6 depends on x5; x7 depends on x6; etc.
    add  x6,  x5,  x2         # x6 = x5 + 2
    sub  x7,  x6,  x1         # x7 = x6 - 1
    xor  x8,  x7,  x6         # x8 = x7 ^ x6
    and  x9,  x8,  x7         # x9 = x8 & x7
    or   x10, x9,  x8         # x10 = x9 | x8

    # Mixed I-type and R-type with dependencies
    andi x11, x10, 0x3F       # x11 = x10 & 0x3F
    slli x11, x11, 1          # x11 <<= 1
    add  x12, x11, x10        # x12 = x11 + x10
    addi x12, x12, -5         # x12 -= 5
    xori x12, x12, 0x0F       # x12 ^= 0x0F
    ori  x13, x12, 0x30       # x13 = x12 | 0x30
    and  x14, x13, x12        # x14 = x13 & x12

    # Self-read-after-write on same dest (provokes bypass/forwarding)
    addi x15, x0, 0           # x15 = 0
    add  x15, x15, x14        # x15 += x14
    add  x15, x15, x13        # x15 += x13
    sub  x15, x15, x12        # x15 -= x12
    xor  x15, x15, x11        # x15 ^= x11

    # Compute shift amount from a previous result and use it
    andi x16, x15, 0x1F       # x16 = shift amount in [0..31]
    sll  x17, x10, x16        # x17 = x10 << (x16)
    srl  x18, x17, x16        # x18 = logical >> back by same amount
    sra  x19, x17, x16        # x19 = arithmetic >> (test sign behavior)

    # Dependency diamond
    add  x20, x5,  x6         # x20 = a
    sub  x21, x7,  x5         # x21 = b
    xor  x22, x20, x21        # x22 = a ^ b
    and  x23, x20, x21        # x23 = a & b
    or   x24, x22, x23        # x24 = (a ^ b) | (a & b)

    # More chains across many ops
    slt  x25, x24, x23        # x25 = x24 < x23 (signed)
    sltu x26, x24, x23        # x26 = x24 < x23 (unsigned)
    add  x27, x26, x25        # x27 = combine comparisons
    addi x27, x27, 7
    andi x27, x27, 0xFF

    # Reuse of the same destination (WAW) to stress rename/ROB
    addi x28, x0, 1
    add  x28, x28, x27        # x28 = prev + x27
    xor  x28, x28, x14        # x28 = prev ^ x14
    and  x28, x28, x13        # x28 = prev & x13
    or   x28, x28, x12        # x28 = prev | x12

    # Another tight RAW loop on x29 with varying op classes
    addi x29, x0, 5
    slli x29, x29, 2
    addi x29, x29, 3
    srli x29, x29, 1
    xori x29, x29, 0xAA
    andi x29, x29, 0x7F
    srai x29, x29, 2

    # Final chain to a known register so the checker can sample
    add  x30, x28, x29
    add  x31, x30, x27        # x31 carries a summary value

    # No branches; program ends by just falling through (testbench will stop)
    slti x0, x0, -256 # indicator for stopping the simulation