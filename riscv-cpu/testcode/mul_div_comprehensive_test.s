.section .text
.globl _start

_start:
    # Load test values
    li x1, 10           # positive value
    li x2, 5            # positive value
    li x3, -8           # negative value (0xFFFFFFF8)
    li x4, -3           # negative value (0xFFFFFFFD)
    li x5, 0x80000000   # most negative 32-bit value
    li x6, 0x7FFFFFFF   # most positive 32-bit value
    li x7, 0            # zero
    
    # ========================================
    # MUL Tests - Lower 32 bits of product
    # ========================================
    mul x8, x1, x2      # x8 = 10 * 5 = 50
    mul x9, x3, x4      # x9 = (-8) * (-3) = 24
    mul x10, x1, x3     # x10 = 10 * (-8) = -80
    mul x11, x1, x7     # x11 = 10 * 0 = 0
    
    # ========================================
    # MULH Tests - Upper 32 bits (signed x signed)
    # ========================================
    mulh x12, x1, x2    # x12 = upper(10 * 5) = 0
    mulh x13, x5, x5    # x13 = upper(0x80000000 * 0x80000000)
    mulh x14, x3, x4    # x14 = upper((-8) * (-3))
    mulh x15, x6, x6    # x15 = upper(0x7FFFFFFF * 0x7FFFFFFF)
    
    # ========================================
    # MULHSU Tests - Upper 32 bits (signed x unsigned)
    # ========================================
    mulhsu x16, x1, x2  # x16 = upper(10 * 5) = 0
    mulhsu x17, x3, x2  # x17 = upper((-8 signed) * (5 unsigned))
    mulhsu x18, x5, x6  # x18 = upper(0x80000000 signed * 0x7FFFFFFF unsigned)
    
    # ========================================
    # MULHU Tests - Upper 32 bits (unsigned x unsigned)
    # ========================================
    mulhu x19, x1, x2   # x19 = upper(10 * 5) = 0
    mulhu x20, x5, x5   # x20 = upper(0x80000000 * 0x80000000 unsigned)
    mulhu x21, x6, x6   # x21 = upper(0x7FFFFFFF * 0x7FFFFFFF unsigned)
    
    # ========================================
    # DIV Tests - Signed division
    # ========================================
    div x22, x1, x2     # x22 = 10 / 5 = 2
    div x23, x2, x1     # x23 = 5 / 10 = 0
    div x24, x3, x4     # x24 = (-8) / (-3) = 2
    div x25, x1, x3     # x25 = 10 / (-8) = -1
    div x26, x1, x7     # x26 = 10 / 0 = -1 (division by zero)
    div x27, x5, x4     # x27 = 0x80000000 / (-3)
    
    # ========================================
    # DIVU Tests - Unsigned division
    # ========================================
    divu x28, x1, x2    # x28 = 10 / 5 = 2
    divu x29, x6, x1    # x29 = 0x7FFFFFFF / 10
    divu x30, x5, x2    # x30 = 0x80000000 / 5 (unsigned)
    divu x31, x1, x7    # x31 = 10 / 0 = 0xFFFFFFFF (division by zero)
    
    # ========================================
    # REM Tests - Signed remainder
    # ========================================
    li x1, 17           # reload with new value
    li x2, 5            # reload with new value
    rem x3, x1, x2      # x3 = 17 % 5 = 2
    li x1, -17          # negative dividend
    li x2, 5            # positive divisor
    rem x4, x1, x2      # x4 = (-17) % 5 = -2
    li x1, 17           # positive dividend
    li x2, -5           # negative divisor
    rem x5, x1, x2      # x5 = 17 % (-5) = 2
    li x1, -17          # negative dividend
    li x2, -5           # negative divisor
    rem x6, x1, x2      # x6 = (-17) % (-5) = -2
    
    # ========================================
    # REMU Tests - Unsigned remainder
    # ========================================
    li x1, 17           # reload
    li x2, 5            # reload
    remu x7, x1, x2     # x7 = 17 % 5 = 2
    li x1, 0x80000000   # large unsigned value
    li x2, 7            # divisor
    remu x8, x1, x2     # x8 = 0x80000000 % 7 (unsigned)
    li x1, 0xFFFFFFFF   # max unsigned value
    li x2, 10           # divisor
    remu x9, x1, x2     # x9 = 0xFFFFFFFF % 10 (unsigned)
    
    # ========================================
    # Edge case: Overflow scenario
    # ========================================
    li x1, 0x80000000   # most negative
    li x2, -1           # divide by -1
    div x10, x1, x2     # x10 = 0x80000000 / (-1) = 0x80000000 (overflow)
    rem x11, x1, x2     # x11 = 0x80000000 % (-1) = 0
    
    # ========================================
    # Dependent operations to test forwarding
    # ========================================
    li x1, 6
    li x2, 3
    mul x3, x1, x2      # x3 = 18
    mul x4, x3, x2      # x4 = 54 (depends on x3)
    div x5, x4, x3      # x5 = 3 (depends on x4 and x3)
    rem x6, x4, x3      # x6 = 0 (depends on x4 and x3)
    
    # Done - infinite loop
    slti x0, x0, -256
