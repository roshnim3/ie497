.section .text
.globl _start

# ============================================================================
# CP2 Comprehensive Test for RV32I + RV32M (No Memory/Branch Instructions)
# Tests all immediate and register instructions required for CP2
# ============================================================================

_start:
    # ========================================================================
    # Test 1: Basic Immediate Arithmetic (ADDI, XORI, ORI, ANDI, SLTI, SLTIU)
    # ========================================================================
    addi x1, x0, 100        # x1 = 100
    addi x2, x0, -50        # x2 = -50 (sign extended)
    xori x3, x1, 0xFF       # x3 = 100 ^ 0xFF = 155
    ori  x4, x2, 0x0F       # x4 = -50 | 0x0F
    andi x5, x1, 0x7F       # x5 = 100 & 0x7F = 100
    slti x6, x1, 101        # x6 = 1 (100 < 101)
    slti x7, x1, 50         # x7 = 0 (100 >= 50)
    sltiu x8, x2, 100       # x8 = 0 (unsigned: -50 as large positive > 100)
    
    # ========================================================================
    # Test 2: Shift Immediate Instructions (SLLI, SRLI, SRAI)
    # ========================================================================
    addi x10, x0, 0x40      # x10 = 64 = 0b01000000
    slli x11, x10, 2        # x11 = 64 << 2 = 256
    srli x12, x11, 3        # x12 = 256 >> 3 = 32 (logical)
    addi x13, x0, -16       # x13 = -16 (0xFFFFFFF0)
    srai x14, x13, 2        # x14 = -16 >> 2 = -4 (arithmetic, sign extend)
    slli x15, x11, 5        # x15 = 256 << 5 = 8192
    srli x16, x15, 8        # x16 = 8192 >> 8 = 32
    
    # ========================================================================
    # Test 3: LUI - Load Upper Immediate
    # ========================================================================
    lui x17, 0x12345        # x17 = 0x12345000
    lui x18, 0xFFFFF        # x18 = 0xFFFFF000
    lui x19, 0               # x19 = 0
    
    # ========================================================================
    # Test 4: Register-Register Arithmetic (ADD, SUB, SLT, SLTU)
    # ========================================================================
    addi x20, x0, 50        # x20 = 50
    addi x21, x0, 30        # x21 = 30
    add  x22, x20, x21      # x22 = 50 + 30 = 80
    sub  x23, x20, x21      # x23 = 50 - 30 = 20
    slt  x24, x21, x20      # x24 = 1 (30 < 50 signed)
    slt  x25, x20, x21      # x25 = 0 (50 >= 30 signed)
    
    addi x26, x0, -10       # x26 = -10
    slt  x27, x26, x21      # x27 = 1 (-10 < 30 signed)
    sltu x28, x26, x21      # x28 = 0 (unsigned: -10 as large > 30)
    
    # ========================================================================
    # Test 5: Logical Operations (AND, OR, XOR)
    # ========================================================================
    addi x1, x0, 0xFF       # x1 = 255 = 0b11111111
    addi x2, x0, 0x0F       # x2 = 15 = 0b00001111
    and  x3, x1, x2         # x3 = 15
    or   x4, x1, x2         # x4 = 255
    xor  x5, x1, x2         # x5 = 240 = 0b11110000
    
    # ========================================================================
    # Test 6: Register-Register Shifts (SLL, SRL, SRA)
    # ========================================================================
    addi x10, x0, 128       # x10 = 128
    addi x11, x0, 3         # x11 = 3 (shift amount)
    sll  x12, x10, x11      # x12 = 128 << 3 = 1024
    srl  x13, x12, x11      # x13 = 1024 >> 3 = 128 (logical)
    
    addi x14, x0, -128      # x14 = -128
    sra  x15, x14, x11      # x15 = -128 >> 3 = -16 (arithmetic)
    
    # ========================================================================
    # Test 7: MUL - Multiply Instructions (Lower 32 bits)
    # ========================================================================
    addi x1, x0, 10         # x1 = 10
    addi x2, x0, 5          # x2 = 5
    mul  x3, x1, x2         # x3 = 10 * 5 = 50
    
    addi x4, x0, -8         # x4 = -8
    addi x5, x0, -3         # x5 = -3
    mul  x6, x4, x5         # x6 = (-8) * (-3) = 24
    
    mul  x7, x1, x4         # x7 = 10 * (-8) = -80
    mul  x8, x1, x0         # x8 = 10 * 0 = 0
    
    # ========================================================================
    # Test 8: MULH - Multiply High (Signed x Signed)
    # ========================================================================
    addi x1, x0, 10
    addi x2, x0, 5
    mulh x9, x1, x2         # x9 = upper(10 * 5) = 0
    
    lui  x10, 0x80000       # x10 = 0x80000000 (most negative)
    mulh x11, x10, x10      # x11 = upper(0x80000000 * 0x80000000)
    
    lui  x12, 0x7FFFF
    addi x12, x12, 0x7FF    # x12 = 0x7FFFFFFF (most positive)
    mulh x13, x12, x12      # x13 = upper(0x7FFFFFFF * 0x7FFFFFFF)
    
    # ========================================================================
    # Test 9: MULHSU - Multiply High (Signed x Unsigned)
    # ========================================================================
    addi x1, x0, 10
    addi x2, x0, 5
    mulhsu x14, x1, x2      # x14 = upper(10 signed * 5 unsigned) = 0
    
    addi x3, x0, -8
    mulhsu x15, x3, x2      # x15 = upper((-8 signed) * (5 unsigned))
    
    # ========================================================================
    # Test 10: MULHU - Multiply High (Unsigned x Unsigned)
    # ========================================================================
    addi x1, x0, 10
    addi x2, x0, 5
    mulhu x16, x1, x2       # x16 = upper(10 * 5 unsigned) = 0
    
    lui  x10, 0x80000       # x10 = 0x80000000
    mulhu x17, x10, x10     # x17 = upper(0x80000000 * 0x80000000 unsigned)
    
    # ========================================================================
    # Test 11: DIV - Signed Division
    # ========================================================================
    addi x1, x0, 10
    addi x2, x0, 5
    div  x18, x1, x2        # x18 = 10 / 5 = 2
    
    div  x19, x2, x1        # x19 = 5 / 10 = 0
    
    addi x3, x0, -8
    addi x4, x0, -3
    div  x20, x3, x4        # x20 = (-8) / (-3) = 2
    
    div  x21, x1, x3        # x21 = 10 / (-8) = -1
    
    # DIV by zero test
    div  x22, x1, x0        # x22 = 10 / 0 = -1 (special case)
    
    # Overflow case
    lui  x5, 0x80000        # x5 = 0x80000000 (most negative)
    addi x6, x0, -1
    div  x23, x5, x6        # x23 = 0x80000000 / (-1) = 0x80000000 (overflow)
    
    # ========================================================================
    # Test 12: DIVU - Unsigned Division
    # ========================================================================
    addi x1, x0, 10
    addi x2, x0, 5
    divu x24, x1, x2        # x24 = 10 / 5 = 2
    
    lui  x10, 0x80000       # x10 = 0x80000000
    divu x25, x10, x2       # x25 = 0x80000000 / 5 (unsigned)
    
    # DIVU by zero test
    divu x26, x1, x0        # x26 = 10 / 0 = 0xFFFFFFFF (special case)
    
    # ========================================================================
    # Test 13: REM - Signed Remainder
    # ========================================================================
    addi x1, x0, 17
    addi x2, x0, 5
    rem  x27, x1, x2        # x27 = 17 % 5 = 2
    
    addi x3, x0, -17
    rem  x28, x3, x2        # x28 = (-17) % 5 = -2
    
    addi x4, x0, -5
    rem  x29, x1, x4        # x29 = 17 % (-5) = 2
    
    rem  x30, x3, x4        # x30 = (-17) % (-5) = -2
    
    # REM by zero test
    rem  x31, x1, x0        # x31 = 17 % 0 = 17 (special case)
    
    # ========================================================================
    # Test 14: REMU - Unsigned Remainder
    # ========================================================================
    addi x1, x0, 17
    addi x2, x0, 5
    remu x3, x1, x2         # x3 = 17 % 5 = 2
    
    lui  x4, 0x80000        # x4 = 0x80000000
    addi x5, x0, 7
    remu x6, x4, x5         # x6 = 0x80000000 % 7 (unsigned)
    
    addi x7, x0, -1         # x7 = 0xFFFFFFFF (max unsigned)
    addi x8, x0, 10
    remu x9, x7, x8         # x9 = 0xFFFFFFFF % 10 (unsigned)
    
    # ========================================================================
    # Test 15: Dependency Chains for OOO Testing
    # ========================================================================
    # Long latency multiply followed by short latency adds
    addi x1, x0, 100
    addi x2, x0, 200
    mul  x3, x1, x2         # Long latency (should complete later)
    
    # These should complete before mul
    addi x4, x0, 10
    addi x5, x0, 20
    add  x6, x4, x5         # x6 = 30
    sub  x7, x5, x4         # x7 = 10
    and  x8, x4, x5         # x8 = 0
    or   x9, x4, x5         # x9 = 30
    
    # Dependent on mul result
    add  x10, x3, x6        # x10 = 20000 + 30 (depends on x3)
    
    # ========================================================================
    # Test 16: Multiple Multiply/Divide in Flight
    # ========================================================================
    addi x11, x0, 12
    addi x12, x0, 4
    addi x13, x0, 7
    addi x14, x0, 3
    
    mul  x15, x11, x12      # x15 = 48
    div  x16, x11, x12      # x16 = 3
    mul  x17, x13, x14      # x17 = 21
    div  x18, x13, x14      # x18 = 2
    
    # Use results
    add  x19, x15, x16      # x19 = 51
    add  x20, x17, x18      # x20 = 23
    add  x21, x19, x20      # x21 = 74
    
    # ========================================================================
    # Test 17: RAW Hazards with Mixed Operation Types
    # ========================================================================
    addi x1, x0, 8
    addi x2, x0, 3
    
    mul  x3, x1, x2         # x3 = 24 (long latency)
    add  x4, x1, x2         # x4 = 11 (short latency)
    sub  x5, x3, x4         # x5 = 24 - 11 = 13 (depends on both)
    
    div  x6, x3, x2         # x6 = 24 / 3 = 8 (depends on x3)
    add  x7, x6, x5         # x7 = 8 + 13 = 21
    
    # ========================================================================
    # Test 18: WAW Hazards (Write-After-Write)
    # ========================================================================
    addi x8, x0, 1
    addi x8, x8, 2          # x8 = 3
    addi x8, x8, 3          # x8 = 6
    addi x8, x8, 4          # x8 = 10 (final value)
    
    mul  x9, x8, x8         # x9 = 100 (depends on final x8)
    
    # ========================================================================
    # Test 19: Extreme Values Testing
    # ========================================================================
    # Max positive
    lui  x10, 0x7FFFF
    addi x10, x10, 0x7FF    # x10 = 0x7FFFFFFF
    
    # Max negative
    lui  x11, 0x80000       # x11 = 0x80000000
    
    # Zero
    add  x12, x0, x0        # x12 = 0
    
    # All ones
    addi x13, x0, -1        # x13 = 0xFFFFFFFF
    
    # Operations with extremes
    add  x14, x10, x11      # x14 = max + min
    xor  x15, x10, x11      # x15 = max ^ min
    and  x16, x10, x13      # x16 = max & all_ones = max
    
    # ========================================================================
    # Test 20: Complex Dependency Graph
    # ========================================================================
    addi x1, x0, 5
    addi x2, x0, 3
    addi x3, x0, 2
    
    mul  x4, x1, x2         # x4 = 15
    mul  x5, x2, x3         # x5 = 6
    add  x6, x4, x5         # x6 = 21 (depends on x4, x5)
    
    div  x7, x4, x2         # x7 = 5 (depends on x4)
    div  x8, x5, x3         # x8 = 3 (depends on x5)
    sub  x9, x7, x8         # x9 = 2 (depends on x7, x8)
    
    mul  x10, x6, x9        # x10 = 42 (depends on x6, x9)

    # ========================================================================
    # HALT
    # ========================================================================
halt:
    slti x0, x0, -256       # Standard halt instruction
