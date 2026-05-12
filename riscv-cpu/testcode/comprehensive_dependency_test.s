.section .text
.globl _start

_start:
    # Initialize base values
    li x1, 100
    li x2, 50
    li x3, 25
    li x4, 10
    li x5, -20
    li x6, 0x7FFFFFFF
    li x7, 0x80000000
    
    # ========================================
    # RAW Dependencies (Read After Write)
    # True dependencies - later instruction needs result from earlier
    # ========================================
    
    # RAW: ALU -> ALU
    add x8, x1, x2          # x8 = 150
    sub x9, x8, x3          # x9 = 125 (depends on x8)
    xor x10, x9, x4         # x10 = 125 ^ 10 (depends on x9)
    
    # RAW: MUL -> ALU
    mul x11, x1, x2         # x11 = 5000
    add x12, x11, x3        # x12 = 5025 (depends on x11)
    
    # RAW: DIV -> ALU
    div x13, x1, x4         # x13 = 10
    sll x14, x13, x3        # x14 = 10 << 25 (depends on x13)
    
    # RAW: ALU -> MUL
    add x15, x1, x2         # x15 = 150
    mul x16, x15, x4        # x16 = 1500 (depends on x15)
    
    # RAW: MUL -> MUL
    mul x17, x1, x2         # x17 = 5000
    mulh x18, x17, x3       # x18 = upper(5000 * 25) (depends on x17)
    
    # RAW: DIV -> DIV
    div x19, x1, x4         # x19 = 10
    rem x20, x19, x3        # x20 = 10 % 25 = 10 (depends on x19)
    
    # RAW: ALU -> DIV
    add x21, x1, x1         # x21 = 200
    div x22, x21, x4        # x22 = 20 (depends on x21)
    
    # RAW Chain: MUL -> DIV -> ALU
    mul x23, x4, x3         # x23 = 250
    div x24, x23, x2        # x24 = 5 (depends on x23)
    add x25, x24, x24       # x25 = 10 (depends on x24)
    
    # ========================================
    # WAR Dependencies (Write After Read)
    # Anti-dependencies - later write overwrites source of earlier read
    # ========================================
    
    # WAR: ALU reads x1, then x1 is overwritten
    add x26, x1, x2         # Reads x1 (100)
    mul x1, x3, x4          # Overwrites x1 (should not affect x26)
    
    # WAR: MUL reads x2, then x2 is overwritten
    mul x27, x2, x3         # Reads x2 (50)
    div x2, x6, x4          # Overwrites x2 (should not affect x27)
    
    # WAR: DIV reads x3, then x3 is overwritten
    div x28, x3, x4         # Reads x3 (25)
    add x3, x5, x5          # Overwrites x3 (should not affect x28)
    
    # WAR Chain: Multiple reads before write
    add x29, x4, x4         # Reads x4
    mul x30, x4, x4         # Reads x4
    sub x4, x6, x6          # Overwrites x4 (should not affect x29 or x30)
    
    # ========================================
    # WAW Dependencies (Write After Write)
    # Output dependencies - multiple writes to same register
    # ========================================
    
    # WAW: ALU overwrites ALU result
    add x31, x5, x5         # First write to x31
    sub x31, x6, x5         # Second write to x31 (should override first)
    
    # WAW: MUL overwrites ALU result
    li x5, 30
    add x5, x1, x2          # First write to x5
    mul x5, x3, x4          # Second write to x5 (should override first)
    
    # WAW: DIV overwrites MUL result
    li x6, 40
    mul x6, x1, x2          # First write to x6
    div x6, x7, x4          # Second write to x6 (should override first)
    
    # WAW: ALU overwrites DIV result
    li x7, 50
    div x7, x1, x4          # First write to x7
    add x7, x2, x3          # Second write to x7 (should override first)
    
    # WAW Chain: Three writes to same register
    li x8, 60
    mul x8, x1, x2          # First write
    div x8, x6, x4          # Second write
    add x8, x3, x4          # Third write (final value should be x3 + x4)
    
    # ========================================
    # RAR Dependencies (Read After Read)
    # No true dependency - both read same register
    # ========================================
    
    # RAR: Multiple ALU operations read same sources
    li x9, 70
    li x10, 80
    add x11, x9, x10        # Reads x9, x10
    sub x12, x9, x10        # Reads x9, x10 (no dependency on x11 or x12)
    xor x13, x9, x10        # Reads x9, x10 (no dependency on previous)
    
    # RAR: MUL and DIV read same sources
    li x14, 90
    li x15, 5
    mul x16, x14, x15       # Reads x14, x15
    div x17, x14, x15       # Reads x14, x15 (no dependency)
    mulh x18, x14, x15      # Reads x14, x15 (no dependency)
    
    # RAR: ALU and MUL read same sources
    li x19, 100
    li x20, 20
    add x21, x19, x20       # Reads x19, x20
    mul x22, x19, x20       # Reads x19, x20 (no dependency)
    
    # ========================================
    # Complex Dependency Chains
    # ========================================
    
    # Mixed RAW chain: ALU -> MUL -> DIV -> ALU
    li x1, 12
    li x2, 6
    add x3, x1, x2          # x3 = 18
    mul x4, x3, x2          # x4 = 108 (RAW on x3)
    div x5, x4, x3          # x5 = 6 (RAW on x4 and x3)
    sub x6, x5, x2          # x6 = 0 (RAW on x5)
    
    # WAR and RAW mixed
    li x7, 24
    li x8, 4
    mul x9, x7, x8          # Reads x7, x8
    add x10, x9, x8         # RAW on x9, reads x8
    div x7, x10, x2         # WAR on x7 (overwrites after read), RAW on x10
    
    # WAW and RAW mixed
    li x11, 15
    mul x12, x11, x2        # First write to x12
    add x12, x11, x11       # WAW on x12
    sub x13, x12, x11       # RAW on x12 (should use second write)
    
    # ========================================
    # ALL ALU Operations with Dependencies
    # ========================================
    
    li x1, 0xFF00
    li x2, 0x00FF
    
    # ADD with RAW
    add x3, x1, x2          # x3 = 0xFFFF
    add x4, x3, x1          # RAW on x3
    
    # SUB with RAW
    sub x5, x1, x2          # x5 = 0xFE01
    sub x6, x5, x3          # RAW on x5
    
    # SLL (Shift Left Logical) with RAW
    li x7, 5
    sll x8, x3, x7          # x8 = 0xFFFF << 5
    sll x9, x8, x7          # RAW on x8
    
    # SRL (Shift Right Logical) with RAW
    srl x10, x8, x7         # x10 = x8 >> 5
    srl x11, x10, x7        # RAW on x10
    
    # SRA (Shift Right Arithmetic) with RAW
    li x12, -1024
    li x13, 2
    sra x14, x12, x13       # x14 = -256
    sra x15, x14, x13       # RAW on x14
    
    # XOR with RAW
    xor x16, x1, x2         # x16 = 0xFF00 ^ 0x00FF
    xor x17, x16, x1        # RAW on x16
    
    # OR with RAW
    or x18, x1, x2          # x18 = 0xFF00 | 0x00FF
    or x19, x18, x3         # RAW on x18
    
    # AND with RAW
    and x20, x1, x2         # x20 = 0xFF00 & 0x00FF = 0
    and x21, x20, x1        # RAW on x20
    
    # SLT (Set Less Than) with RAW
    li x22, 100
    li x23, 200
    slt x24, x22, x23       # x24 = 1 (100 < 200)
    slt x25, x24, x22       # RAW on x24
    
    # SLTU (Set Less Than Unsigned) with RAW
    li x26, -1
    sltu x27, x22, x26      # x27 = 1 (100 < 0xFFFFFFFF unsigned)
    sltu x28, x27, x23      # RAW on x27
    
    # ========================================
    # ALL MUL/DIV Operations with Dependencies
    # ========================================
    
    li x1, 1000
    li x2, 100
    li x3, -50
    
    # MUL with RAW chain
    mul x4, x1, x2          # x4 = 100000
    mul x5, x4, x2          # RAW on x4
    
    # MULH (signed high) with RAW
    mulh x6, x1, x1         # x6 = upper(1000 * 1000)
    mulh x7, x6, x2         # RAW on x6
    
    # MULHSU (signed * unsigned high) with RAW
    mulhsu x8, x3, x2       # x8 = upper(-50 * 100 unsigned)
    mulhsu x9, x8, x1       # RAW on x8
    
    # MULHU (unsigned high) with RAW
    mulhu x10, x1, x2       # x10 = upper(1000 * 100 unsigned)
    mulhu x11, x10, x10     # RAW on x10
    
    # DIV (signed) with RAW chain
    div x12, x1, x2         # x12 = 10
    div x13, x12, x2        # RAW on x12
    
    # DIVU (unsigned) with RAW
    li x14, 0x80000000
    divu x15, x14, x2       # x15 = 0x80000000 / 100 (unsigned)
    divu x16, x15, x2       # RAW on x15
    
    # REM (signed remainder) with RAW
    li x17, 1234
    li x18, 100
    rem x19, x17, x18       # x19 = 34
    rem x20, x19, x18       # RAW on x19
    
    # REMU (unsigned remainder) with RAW
    remu x21, x14, x18      # x21 = 0x80000000 % 100 (unsigned)
    remu x22, x21, x18      # RAW on x21
    
    # ========================================
    # Stress Test: Maximum Dependencies
    # ========================================
    
    # Long RAW chain (10 dependent instructions)
    li x1, 1
    add x2, x1, x1          # x2 = 2
    mul x3, x2, x2          # x3 = 4 (RAW on x2)
    add x4, x3, x3          # x4 = 8 (RAW on x3)
    mul x5, x4, x2          # x5 = 16 (RAW on x4)
    div x6, x5, x2          # x6 = 8 (RAW on x5)
    add x7, x6, x6          # x7 = 16 (RAW on x6)
    mul x8, x7, x2          # x8 = 32 (RAW on x7)
    div x9, x8, x4          # x9 = 4 (RAW on x8)
    add x10, x9, x9         # x10 = 8 (RAW on x9)
    mul x11, x10, x10       # x11 = 64 (RAW on x10)
    
    # Multiple WAW to same register
    li x12, 0
    add x12, x1, x1         # Write 1
    mul x12, x2, x2         # Write 2
    div x12, x5, x2         # Write 3
    sub x12, x8, x7         # Write 4
    xor x12, x9, x10        # Write 5 (final value)
    
    # Parallel independent operations (RAR)
    li x13, 42
    li x14, 7
    add x15, x13, x14       # Independent
    sub x16, x13, x14       # Independent (reads same x13, x14)
    mul x17, x13, x14       # Independent (reads same x13, x14)
    div x18, x13, x14       # Independent (reads same x13, x14)
    xor x19, x13, x14       # Independent (reads same x13, x14)
    
    # Done - infinite loop
    slti x0, x0, -256
