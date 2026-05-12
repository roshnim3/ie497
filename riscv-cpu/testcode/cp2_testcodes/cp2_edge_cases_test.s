.section .text
.globl _start

# ============================================================================
# CP2 Edge Cases Test
# Tests all corner cases for RV32IM instructions
# - Overflow scenarios
# - Division by zero
# - Signed/unsigned boundary conditions
# - Shift amount edge cases
# ============================================================================

_start:
    # ========================================================================
    # Test 1: Division by Zero Edge Cases (per RISC-V spec)
    # ========================================================================
    
    addi x1, x0, 42
    
    # DIV by zero: should return -1
    div  x2, x1, x0         # x2 = -1
    
    # DIVU by zero: should return 2^XLEN - 1 (0xFFFFFFFF)
    divu x3, x1, x0         # x3 = 0xFFFFFFFF
    
    # REM by zero: should return dividend
    rem  x4, x1, x0         # x4 = 42
    
    # REMU by zero: should return dividend
    remu x5, x1, x0         # x5 = 42
    
    # Verify results
    addi x6, x0, -1
    sub  x7, x2, x6         # x7 should be 0 if div by zero worked
    
    # ========================================================================
    # Test 2: Division Overflow (most negative / -1)
    # ========================================================================
    
    lui  x10, 0x80000       # x10 = 0x80000000 (most negative int32)
    addi x11, x0, -1        # x11 = -1
    
    # DIV overflow: 0x80000000 / -1 should return 0x80000000 (overflow)
    div  x12, x10, x11      # x12 = 0x80000000
    
    # REM overflow: 0x80000000 % -1 should return 0
    rem  x13, x10, x11      # x13 = 0
    
    # DIVU should work normally (no overflow in unsigned)
    divu x14, x10, x11      # x14 = 0 (0x80000000 / 0xFFFFFFFF = 0)
    
    # REMU should work normally
    remu x15, x10, x11      # x15 = 0x80000000
    
    # ========================================================================
    # Test 3: Signed Multiplication Edge Cases
    # ========================================================================
    
    lui  x1, 0x80000        # x1 = 0x80000000 (most negative)
    lui  x2, 0x7FFFF
    addi x2, x2, 0x7FF      # x2 = 0x7FFFFFFF (most positive)
    addi x3, x0, -1         # x3 = -1
    
    # Most negative * most negative
    mul  x4, x1, x1         # x4 = lower 32 bits
    mulh x5, x1, x1         # x5 = upper 32 bits (should be 0x40000000)
    
    # Most positive * most positive
    mul  x6, x2, x2         # x6 = lower 32 bits (0x00000001)
    mulh x7, x2, x2         # x7 = upper 32 bits (0x3FFFFFFF)
    
    # Most negative * -1
    mul  x8, x1, x3         # x8 = 0x80000000 (overflow in 32 bits)
    mulh x9, x1, x3         # x9 = upper bits
    
    # Most positive * -1
    mul  x10, x2, x3        # x10 = 0x80000001
    mulh x11, x2, x3        # x11 = 0xFFFFFFFF (sign extension)
    
    # ========================================================================
    # Test 4: Unsigned Multiplication Edge Cases
    # ========================================================================
    
    lui  x1, 0xFFFFF
    addi x1, x1, 0x7FF      # x1 = 0xFFFFFFFF (max unsigned)
    addi x2, x0, 2
    
    # Max unsigned * 2
    mul  x3, x1, x2         # x3 = 0xFFFFFFFE (lower)
    mulhu x4, x1, x2        # x4 = 0x00000001 (upper)
    
    # Max unsigned * max unsigned
    mul  x5, x1, x1         # x5 = 0x00000001 (lower)
    mulhu x6, x1, x1        # x6 = 0xFFFFFFFE (upper)
    
    # ========================================================================
    # Test 5: Mixed Signed/Unsigned Multiplication (MULHSU)
    # ========================================================================
    
    addi x1, x0, -1         # x1 = -1 (signed)
    lui  x2, 0xFFFFF
    addi x2, x2, 0x7FF      # x2 = 0xFFFFFFFF (unsigned interpretation)
    
    # -1 (signed) * 0xFFFFFFFF (unsigned)
    mul   x3, x1, x2        # x3 = lower bits
    mulhsu x4, x1, x2       # x4 = upper bits (signed x unsigned)
    
    lui  x5, 0x80000        # x5 = 0x80000000 (most negative signed)
    addi x6, x0, 2
    
    # 0x80000000 (signed) * 2 (unsigned)
    mul   x7, x5, x6        # x7 = lower bits
    mulhsu x8, x5, x6       # x8 = upper bits
    
    # ========================================================================
    # Test 6: Shift Amount Edge Cases
    # ========================================================================
    
    addi x1, x0, 1          # x1 = 1
    
    # Shift by 0
    slli x2, x1, 0          # x2 = 1 (no shift)
    srli x3, x1, 0          # x3 = 1
    srai x4, x1, 0          # x4 = 1
    
    # Shift by maximum (31)
    slli x5, x1, 31         # x5 = 0x80000000
    
    lui  x10, 0x80000       # x10 = 0x80000000
    srli x6, x10, 31        # x6 = 1 (logical shift)
    srai x7, x10, 31        # x7 = 0xFFFFFFFF (arithmetic shift, sign extend)
    
    # Shift amount from register (only lower 5 bits matter)
    addi x11, x0, 33        # x11 = 33 = 0b100001 -> shift by 1
    sll  x8, x1, x11        # x8 = 2 (shift by 1, not 33)
    
    addi x12, x0, 63        # x12 = 63 = 0b111111 -> shift by 31
    sll  x9, x1, x12        # x9 = 0x80000000 (shift by 31)
    
    # ========================================================================
    # Test 7: Zero Register (x0) as Source and Destination
    # ========================================================================
    
    addi x1, x0, 100
    addi x2, x0, 50
    
    # Operations with x0 as source
    add  x3, x1, x0         # x3 = 100 (x0 is always 0)
    mul  x4, x1, x0         # x4 = 0
    or   x5, x1, x0         # x5 = 100
    and  x6, x1, x0         # x6 = 0
    
    # Operations writing to x0 (should have no effect)
    add  x0, x1, x2         # x0 still 0
    mul  x0, x1, x2         # x0 still 0
    lui  x0, 0x12345        # x0 still 0
    
    # Verify x0 is still 0
    add  x7, x0, x0         # x7 = 0
    or   x8, x0, x0         # x8 = 0
    
    # ========================================================================
    # Test 8: Immediate Values Edge Cases
    # ========================================================================
    
    # Maximum positive immediate (11 bits for I-type)
    addi x1, x0, 2047       # x1 = 2047 (max positive)
    
    # Minimum negative immediate
    addi x2, x0, -2048      # x2 = -2048 (max negative)
    
    # Sign extension of immediate
    xori x3, x0, 0x7FF      # x3 = 0x7FF (not sign extended)
    xori x4, x0, -1         # x4 = 0xFFFFFFFF (sign extended from -1)
    
    ori  x5, x0, 0x7FF      # x5 = 0x7FF
    andi x6, x0, 0x7FF      # x6 = 0 (AND with zero)
    
    # ========================================================================
    # Test 9: LUI Edge Cases
    # ========================================================================
    
    # LUI with 0
    lui  x1, 0              # x1 = 0
    
    # LUI with all 1s (20 bits)
    lui  x2, 0xFFFFF        # x2 = 0xFFFFF000
    
    # LUI with pattern
    lui  x3, 0x55555        # x3 = 0x55555000
    lui  x4, 0xAAAAA        # x4 = 0xAAAAA000
    
    # Combine LUI with ADDI to make full 32-bit constant
    lui  x5, 0x12345
    addi x5, x5, 0x678      # x5 = 0x12345678
    
    # ========================================================================
    # Test 10: Comparison Edge Cases (SLT, SLTU)
    # ========================================================================
    
    addi x1, x0, -1         # x1 = -1
    addi x2, x0, 1          # x2 = 1
    lui  x3, 0x80000        # x3 = 0x80000000 (most negative)
    lui  x4, 0x7FFFF
    addi x4, x4, 0x7FF      # x4 = 0x7FFFFFFF (most positive)
    
    # Signed comparison
    slt  x5, x1, x2         # x5 = 1 (-1 < 1 signed)
    slt  x6, x2, x1         # x6 = 0 (1 > -1 signed)
    slt  x7, x3, x4         # x7 = 1 (most negative < most positive)
    slt  x8, x4, x3         # x8 = 0
    
    # Unsigned comparison
    sltu x9, x1, x2         # x9 = 0 (0xFFFFFFFF > 1 unsigned)
    sltu x10, x2, x1        # x10 = 1 (1 < 0xFFFFFFFF unsigned)
    sltu x11, x3, x4        # x11 = 0 (0x80000000 > 0x7FFFFFFF unsigned)
    sltu x12, x4, x3        # x12 = 1
    
    # Equal values
    slt  x13, x1, x1        # x13 = 0 (equal)
    sltu x14, x2, x2        # x14 = 0 (equal)
    
    # With zero
    slt  x15, x0, x2        # x15 = 1 (0 < 1)
    slt  x16, x1, x0        # x16 = 1 (-1 < 0)
    sltu x17, x0, x2        # x17 = 1 (0 < 1)
    sltu x18, x1, x0        # x18 = 0 (0xFFFFFFFF > 0 unsigned)
    
    # ========================================================================
    # Test 11: Remainder Sign Rules (per RISC-V spec)
    # ========================================================================
    
    # Remainder takes sign of dividend, divisor sign doesn't matter
    addi x1, x0, 17
    addi x2, x0, 5
    addi x3, x0, -17
    addi x4, x0, -5
    
    rem  x5, x1, x2         # x5 = 2 (pos / pos = pos rem)
    rem  x6, x3, x2         # x6 = -2 (neg / pos = neg rem)
    rem  x7, x1, x4         # x7 = 2 (pos / neg = pos rem)
    rem  x8, x3, x4         # x8 = -2 (neg / neg = neg rem)
    
    # ========================================================================
    # Test 12: All-ones pattern
    # ========================================================================
    
    addi x1, x0, -1         # x1 = 0xFFFFFFFF
    
    # Shifts
    slli x2, x1, 1          # x2 = 0xFFFFFFFE
    srli x3, x1, 1          # x3 = 0x7FFFFFFF
    srai x4, x1, 1          # x4 = 0xFFFFFFFF (arithmetic)
    
    # Arithmetic
    add  x5, x1, x1         # x5 = 0xFFFFFFFE (-2)
    sub  x6, x0, x1         # x6 = 1 (0 - (-1))
    
    # Logical
    and  x7, x1, x1         # x7 = 0xFFFFFFFF
    or   x8, x1, x0         # x8 = 0xFFFFFFFF
    xor  x9, x1, x1         # x9 = 0 (same value XOR)
    
    # Multiply
    mul  x10, x1, x1        # x10 = 1
    mulh x11, x1, x1        # x11 = 0
    
    # Divide
    div  x12, x1, x1        # x12 = 1
    rem  x13, x1, x1        # x13 = 0

    # ========================================================================
    # HALT
    # ========================================================================
halt:
    slti x0, x0, -256
