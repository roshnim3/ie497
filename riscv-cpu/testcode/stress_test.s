# =============================================================================
# Comprehensive Stress Test for Out-of-Order CPU
# =============================================================================
# Tests:
# - Fills all Reservation Stations (ALU=8, MUL=8, DIV=8)
# - Fills ROB (64 entries)
# - Fills Fetch Queue (16 entries)
# - All ALU operations (ADD, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, SUB)
# - All MUL/DIV operations (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU)
# - All dependency types: RAW, WAR, WAW, RAR
# =============================================================================

.section .text
.globl _start

_start:
    # Initialize base registers with diverse values
    li x1, 0x12345678
    li x2, 0x87654321
    li x3, 0xFEDCBA98
    li x4, 0x89ABCDEF
    li x5, 100
    li x6, 50
    li x7, -100
    li x8, -50
    li x9, 0xFFFFFFFF
    li x10, 0x7FFFFFFF
    li x11, 0x80000000
    li x12, 1
    li x13, 2
    li x14, 4
    li x15, 8
    li x16, 16

    # =============================================================================
    # SECTION 1: STRESS TEST - Fill all Reservation Stations simultaneously
    # =============================================================================
    
    # --- Fill ALU RS (8 entries) with long dependency chains ---
    add  x17, x1, x2      # ALU-1: RAR (reads x1, x2)
    sub  x18, x3, x4      # ALU-2: RAR (reads x3, x4)
    xor  x19, x5, x6      # ALU-3: RAR (reads x5, x6)
    or   x20, x7, x8      # ALU-4: RAR (reads x7, x8)
    and  x21, x9, x10     # ALU-5: RAR (reads x9, x10)
    sll  x22, x11, x12    # ALU-6: RAR (reads x11, x12)
    srl  x23, x13, x14    # ALU-7: RAR (reads x13, x14)
    sra  x24, x15, x16    # ALU-8: RAR (reads x15, x16)
    
    # --- Fill MUL RS (8 entries) with long-latency operations ---
    mul    x25, x1, x2    # MUL-1: RAR (reads x1, x2)
    mulh   x26, x3, x4    # MUL-2: RAR (reads x3, x4)
    mulhsu x27, x5, x6    # MUL-3: RAR (reads x5, x6)
    mulhu  x28, x7, x8    # MUL-4: RAR (reads x7, x8)
    mul    x29, x9, x10   # MUL-5: RAR (reads x9, x10)
    mulh   x30, x11, x12  # MUL-6: RAR (reads x11, x12)
    mulhsu x31, x13, x14  # MUL-7: RAR (reads x13, x14)
    mulhu  x17, x15, x16  # MUL-8: RAR + WAW (reads x15, x16; writes x17)
    
    # --- Fill DIV RS (8 entries) with very long-latency operations ---
    div   x18, x1, x5     # DIV-1: RAR + WAW (reads x1, x5; writes x18)
    divu  x19, x2, x6     # DIV-2: RAR + WAW (reads x2, x6; writes x19)
    rem   x20, x3, x7     # DIV-3: RAR + WAW (reads x3, x7; writes x20)
    remu  x21, x4, x8     # DIV-4: RAR + WAW (reads x4, x8; writes x21)
    div   x22, x9, x12    # DIV-5: RAR + WAW (reads x9, x12; writes x22)
    divu  x23, x10, x13   # DIV-6: RAR + WAW (reads x10, x13; writes x23)
    rem   x24, x11, x14   # DIV-7: RAR + WAW (reads x11, x14; writes x24)
    remu  x25, x16, x15   # DIV-8: RAR + WAW (reads x16, x15; writes x25)

    # =============================================================================
    # SECTION 2: RAW Dependencies - Read After Write
    # =============================================================================
    
    # RAW chain through ALU operations
    add  x17, x1, x2      # Write x17
    sub  x18, x17, x3     # RAW: Read x17 (depends on previous add)
    xor  x19, x18, x4     # RAW: Read x18 (depends on previous sub)
    or   x20, x19, x5     # RAW: Read x19 (depends on previous xor)
    and  x21, x20, x6     # RAW: Read x20 (depends on previous or)
    sll  x22, x21, x12    # RAW: Read x21 (depends on previous and)
    srl  x23, x22, x12    # RAW: Read x22 (depends on previous sll)
    sra  x24, x23, x12    # RAW: Read x23 (depends on previous srl)
    
    # RAW chain through MUL operations
    mul    x25, x1, x2    # Write x25
    mulh   x26, x25, x3   # RAW: Read x25 (depends on previous mul)
    mulhsu x27, x26, x4   # RAW: Read x26 (depends on previous mulh)
    mulhu  x28, x27, x5   # RAW: Read x27 (depends on previous mulhsu)
    mul    x29, x28, x6   # RAW: Read x28 (depends on previous mulhu)
    
    # RAW chain through DIV operations
    div  x30, x10, x5     # Write x30
    rem  x31, x30, x6     # RAW: Read x30 (depends on previous div)
    divu x17, x31, x7     # RAW: Read x31 (depends on previous rem)
    remu x18, x17, x8     # RAW: Read x17 (depends on previous divu)
    
    # Mixed RAW dependencies across different FUs
    add  x19, x1, x2      # ALU: Write x19
    mul  x20, x19, x3     # MUL: RAW on x19
    div  x21, x20, x5     # DIV: RAW on x20
    sub  x22, x21, x6     # ALU: RAW on x21
    mulh x23, x22, x7     # MUL: RAW on x22
    rem  x24, x23, x8     # DIV: RAW on x23
    
    # =============================================================================
    # SECTION 3: WAR Dependencies - Write After Read
    # =============================================================================
    
    # WAR: Read x1, then write x1
    add  x17, x1, x2      # Read x1
    mul  x18, x3, x4      # Unrelated operation
    sub  x1, x5, x6       # WAR: Write x1 (after reading in add)
    
    # WAR: Read x2, then write x2
    xor  x19, x2, x7      # Read x2
    div  x20, x8, x9      # Unrelated operation
    or   x2, x10, x11     # WAR: Write x2 (after reading in xor)
    
    # WAR: Read x3, then write x3
    and  x21, x3, x12     # Read x3
    mulh x22, x13, x14    # Unrelated operation
    sll  x3, x15, x12     # WAR: Write x3 (after reading in and)
    
    # Complex WAR with multiple readers
    add  x23, x4, x5      # Read x4
    sub  x24, x4, x6      # Read x4 again (RAR with previous)
    mul  x25, x7, x8      # Unrelated operation
    xor  x4, x9, x10      # WAR: Write x4 (after both reads)
    
    # =============================================================================
    # SECTION 4: WAW Dependencies - Write After Write
    # =============================================================================
    
    # WAW: Two writes to x17
    add  x17, x1, x2      # First write to x17
    sub  x17, x3, x4      # WAW: Second write to x17
    
    # WAW: Two writes to x18
    mul  x18, x5, x6      # First write to x18
    div  x18, x7, x8      # WAW: Second write to x18
    
    # WAW: Three writes to x19
    xor  x19, x9, x10     # First write to x19
    or   x19, x11, x12    # WAW: Second write to x19
    and  x19, x13, x14    # WAW: Third write to x19
    
    # WAW chain with different FUs
    add  x20, x1, x2      # ALU: Write x20
    mul  x20, x3, x4      # MUL: WAW on x20
    div  x20, x5, x6      # DIV: WAW on x20
    sub  x20, x7, x8      # ALU: WAW on x20
    
    # =============================================================================
    # SECTION 5: RAR Dependencies - Read After Read
    # =============================================================================
    
    # Multiple reads of x1
    add  x17, x1, x2      # Read x1
    sub  x18, x1, x3      # RAR: Read x1 again
    xor  x19, x1, x4      # RAR: Read x1 again
    mul  x20, x1, x5      # RAR: Read x1 again
    div  x21, x1, x6      # RAR: Read x1 again
    
    # Multiple reads of x2
    or   x22, x2, x7      # Read x2
    and  x23, x2, x8      # RAR: Read x2 again
    mulh x24, x2, x9      # RAR: Read x2 again
    rem  x25, x2, x10     # RAR: Read x2 again
    
    # =============================================================================
    # SECTION 6: Complex Mixed Dependencies
    # =============================================================================
    
    # Mix RAW + WAW + RAR
    add  x26, x11, x12    # Write x26
    sub  x27, x26, x13    # RAW: Read x26
    mul  x26, x14, x15    # WAW: Write x26 again
    xor  x28, x26, x16    # RAW: Read x26 (depends on mul, not add)
    div  x26, x1, x2      # WAW: Write x26 third time
    
    # Mix RAR + WAR + WAW
    or   x29, x3, x4      # Read x3, x4
    and  x30, x3, x5      # RAR: Read x3 again
    sll  x3, x6, x12      # WAR: Write x3
    mul  x31, x4, x7      # RAR: Read x4 again
    sub  x4, x8, x9       # WAR: Write x4
    
    # =============================================================================
    # SECTION 7: Fill ROB - 64 consecutive operations
    # =============================================================================
    
    add  x17, x1, x2      # ROB-1
    sub  x18, x3, x4      # ROB-2
    xor  x19, x5, x6      # ROB-3
    or   x20, x7, x8      # ROB-4
    and  x21, x9, x10     # ROB-5
    sll  x22, x11, x12    # ROB-6
    srl  x23, x13, x14    # ROB-7
    sra  x24, x15, x16    # ROB-8
    mul  x25, x1, x2      # ROB-9
    mulh x26, x3, x4      # ROB-10
    mulhsu x27, x5, x6    # ROB-11
    mulhu x28, x7, x8     # ROB-12
    div  x29, x9, x5      # ROB-13
    divu x30, x10, x6     # ROB-14
    rem  x31, x11, x7     # ROB-15
    remu x17, x12, x8     # ROB-16
    add  x18, x13, x14    # ROB-17
    sub  x19, x15, x16    # ROB-18
    xor  x20, x1, x3      # ROB-19
    or   x21, x2, x4      # ROB-20
    and  x22, x5, x7      # ROB-21
    sll  x23, x6, x12     # ROB-22
    srl  x24, x8, x12     # ROB-23
    sra  x25, x9, x12     # ROB-24
    mul  x26, x10, x11    # ROB-25
    mulh x27, x12, x13    # ROB-26
    mulhsu x28, x14, x15  # ROB-27
    mulhu x29, x16, x1    # ROB-28
    div  x30, x2, x5      # ROB-29
    divu x31, x3, x6      # ROB-30
    rem  x17, x4, x7      # ROB-31
    remu x18, x8, x9      # ROB-32
    add  x19, x10, x12    # ROB-33
    sub  x20, x11, x13    # ROB-34
    xor  x21, x14, x16    # ROB-35
    or   x22, x15, x1     # ROB-36
    and  x23, x2, x4      # ROB-37
    sll  x24, x3, x12     # ROB-38
    srl  x25, x5, x12     # ROB-39
    sra  x26, x6, x12     # ROB-40
    mul  x27, x7, x9      # ROB-41
    mulh x28, x8, x10     # ROB-42
    mulhsu x29, x11, x13  # ROB-43
    mulhu x30, x12, x14   # ROB-44
    div  x31, x15, x5     # ROB-45
    divu x17, x16, x6     # ROB-46
    rem  x18, x1, x7      # ROB-47
    remu x19, x2, x8      # ROB-48
    add  x20, x3, x5      # ROB-49
    sub  x21, x4, x6      # ROB-50
    xor  x22, x7, x9      # ROB-51
    or   x23, x8, x10     # ROB-52
    and  x24, x11, x13    # ROB-53
    sll  x25, x12, x12    # ROB-54
    srl  x26, x14, x12    # ROB-55
    sra  x27, x15, x12    # ROB-56
    mul  x28, x16, x1     # ROB-57
    mulh x29, x2, x4      # ROB-58
    mulhsu x30, x3, x5    # ROB-59
    mulhu x31, x6, x8     # ROB-60
    div  x17, x7, x5      # ROB-61
    divu x18, x9, x6      # ROB-62
    rem  x19, x10, x7     # ROB-63
    remu x20, x11, x8     # ROB-64

    # =============================================================================
    # SECTION 8: Maximum Dependency Depth
    # =============================================================================
    
    # 20-level deep RAW dependency chain through ALU
    add  x17, x1, x2      # Level 1
    add  x17, x17, x3     # Level 2: RAW on x17
    add  x17, x17, x4     # Level 3: RAW on x17
    add  x17, x17, x5     # Level 4: RAW on x17
    add  x17, x17, x6     # Level 5: RAW on x17
    add  x17, x17, x7     # Level 6: RAW on x17
    add  x17, x17, x8     # Level 7: RAW on x17
    add  x17, x17, x9     # Level 8: RAW on x17
    add  x17, x17, x10    # Level 9: RAW on x17
    add  x17, x17, x11    # Level 10: RAW on x17
    add  x17, x17, x12    # Level 11: RAW on x17
    add  x17, x17, x13    # Level 12: RAW on x17
    add  x17, x17, x14    # Level 13: RAW on x17
    add  x17, x17, x15    # Level 14: RAW on x17
    add  x17, x17, x16    # Level 15: RAW on x17
    add  x17, x17, x1     # Level 16: RAW on x17
    add  x17, x17, x2     # Level 17: RAW on x17
    add  x17, x17, x3     # Level 18: RAW on x17
    add  x17, x17, x4     # Level 19: RAW on x17
    add  x17, x17, x5     # Level 20: RAW on x17
    
    # 15-level deep RAW dependency chain through MUL
    mul  x18, x1, x2      # Level 1
    mul  x18, x18, x3     # Level 2: RAW on x18
    mul  x18, x18, x4     # Level 3: RAW on x18
    mul  x18, x18, x5     # Level 4: RAW on x18
    mul  x18, x18, x6     # Level 5: RAW on x18
    mul  x18, x18, x7     # Level 6: RAW on x18
    mul  x18, x18, x8     # Level 7: RAW on x18
    mul  x18, x18, x9     # Level 8: RAW on x18
    mul  x18, x18, x10    # Level 9: RAW on x18
    mul  x18, x18, x11    # Level 10: RAW on x18
    mul  x18, x18, x12    # Level 11: RAW on x18
    mul  x18, x18, x13    # Level 12: RAW on x18
    mul  x18, x18, x14    # Level 13: RAW on x18
    mul  x18, x18, x15    # Level 14: RAW on x18
    mul  x18, x18, x16    # Level 15: RAW on x18
    
    # 10-level deep RAW dependency chain through DIV
    div  x19, x10, x5     # Level 1
    div  x19, x19, x6     # Level 2: RAW on x19
    div  x19, x19, x7     # Level 3: RAW on x19
    div  x19, x19, x8     # Level 4: RAW on x19
    div  x19, x19, x5     # Level 5: RAW on x19
    div  x19, x19, x6     # Level 6: RAW on x19
    div  x19, x19, x7     # Level 7: RAW on x19
    div  x19, x19, x8     # Level 8: RAW on x19
    div  x19, x19, x5     # Level 9: RAW on x19
    div  x19, x19, x6     # Level 10: RAW on x19

    # =============================================================================
    # SECTION 9: Interleaved FU Dependencies
    # =============================================================================
    
    # Alternate between ALU, MUL, DIV with dependencies
    add  x20, x1, x2      # ALU
    mul  x21, x20, x3     # MUL: RAW on x20
    div  x22, x21, x5     # DIV: RAW on x21
    sub  x23, x22, x6     # ALU: RAW on x22
    mulh x24, x23, x7     # MUL: RAW on x23
    rem  x25, x24, x8     # DIV: RAW on x24
    xor  x26, x25, x9     # ALU: RAW on x25
    mulhsu x27, x26, x10  # MUL: RAW on x26
    divu x28, x27, x11    # DIV: RAW on x27
    or   x29, x28, x12    # ALU: RAW on x28
    mulhu x30, x29, x13   # MUL: RAW on x29
    remu x31, x30, x14    # DIV: RAW on x30
    and  x17, x31, x15    # ALU: RAW on x31
    mul  x18, x17, x16    # MUL: RAW on x17
    div  x19, x18, x5     # DIV: RAW on x18

    # =============================================================================
    # SECTION 10: All ALU Operations Test
    # =============================================================================
    
    add  x20, x1, x2      # ADD
    sub  x21, x3, x4      # SUB
    sll  x22, x5, x12     # SLL (shift left logical)
    slt  x23, x7, x8      # SLT (set less than signed)
    sltu x24, x9, x10     # SLTU (set less than unsigned)
    xor  x25, x11, x13    # XOR
    srl  x26, x14, x12    # SRL (shift right logical)
    sra  x27, x15, x12    # SRA (shift right arithmetic)
    or   x28, x16, x1     # OR
    and  x29, x2, x4      # AND
    
    # ALU immediate variants
    addi  x30, x5, 100    # ADDI
    slti  x31, x6, -50    # SLTI
    sltiu x17, x7, 200    # SLTIU
    xori  x18, x8, 0xFF   # XORI
    ori   x19, x9, 0xF0   # ORI
    andi  x20, x10, 0x0F  # ANDI
    slli  x21, x11, 5     # SLLI
    srli  x22, x12, 3     # SRLI
    srai  x23, x13, 4     # SRAI

    # =============================================================================
    # SECTION 11: All MUL/DIV Operations Test
    # =============================================================================
    
    # All multiply variants
    mul    x24, x1, x2    # MUL: lower 32 bits
    mulh   x25, x3, x4    # MULH: upper 32 bits (signed × signed)
    mulhsu x26, x5, x6    # MULHSU: upper 32 bits (signed × unsigned)
    mulhu  x27, x7, x8    # MULHU: upper 32 bits (unsigned × unsigned)
    
    # All divide variants
    div    x28, x9, x5    # DIV: signed division
    divu   x29, x10, x6   # DIVU: unsigned division
    rem    x30, x11, x7   # REM: signed remainder
    remu   x31, x12, x8   # REMU: unsigned remainder
    
    # Edge cases for MUL/DIV
    mul    x17, x9, x9    # Multiply -1 × -1
    mulh   x18, x10, x11  # Multiply max positive × min negative
    div    x19, x10, x12  # Divide max positive by small value
    div    x20, x11, x12  # Divide min negative by small value
    rem    x21, x10, x5   # Remainder with max positive
    rem    x22, x11, x5   # Remainder with min negative

    # =============================================================================
    # SECTION 12: Register Pressure Test
    # =============================================================================
    
    # Use all 32 registers simultaneously
    add  x1, x2, x3
    sub  x2, x3, x4
    xor  x3, x4, x5
    or   x4, x5, x6
    and  x5, x6, x7
    sll  x6, x7, x8
    srl  x7, x8, x9
    sra  x8, x9, x10
    mul  x9, x10, x11
    mulh x10, x11, x12
    div  x11, x12, x13
    rem  x12, x13, x14
    add  x13, x14, x15
    sub  x14, x15, x16
    xor  x15, x16, x1
    or   x16, x1, x2
    and  x17, x2, x3
    sll  x18, x3, x4
    srl  x19, x4, x5
    sra  x20, x5, x6
    mul  x21, x6, x7
    mulh x22, x7, x8
    div  x23, x8, x9
    rem  x24, x9, x10
    add  x25, x10, x11
    sub  x26, x11, x12
    xor  x27, x12, x13
    or   x28, x13, x14
    and  x29, x14, x15
    sll  x30, x15, x16
    srl  x31, x16, x1

    # =============================================================================
    # SECTION 13: Final Mixed Stress Test
    # =============================================================================
    
    # Create maximum pressure on all structures simultaneously
    add  x1, x2, x3       # ALU RS
    mul  x4, x5, x6       # MUL RS
    div  x7, x8, x9       # DIV RS
    sub  x10, x11, x12    # ALU RS
    mulh x13, x14, x15    # MUL RS
    rem  x16, x1, x5      # DIV RS: RAW on x1
    xor  x17, x4, x7      # ALU RS: RAW on x4, x7
    mulhsu x18, x10, x13  # MUL RS: RAW on x10, x13
    divu x19, x16, x6     # DIV RS: RAW on x16
    or   x20, x17, x18    # ALU RS: RAW on x17, x18
    mulhu x21, x19, x2    # MUL RS: RAW on x19
    remu x22, x20, x8     # DIV RS: RAW on x20
    and  x23, x21, x22    # ALU RS: RAW on x21, x22
    mul  x24, x23, x3     # MUL RS: RAW on x23
    div  x25, x24, x9     # DIV RS: RAW on x24
    sll  x26, x25, x12    # ALU RS: RAW on x25
    
    # Final accumulation to ensure all operations complete
    add  x31, x1, x2
    add  x31, x31, x3
    add  x31, x31, x4
    add  x31, x31, x5
    add  x31, x31, x6
    add  x31, x31, x7
    add  x31, x31, x8
    add  x31, x31, x9
    add  x31, x31, x10

halt:
    slti x0, x0, -256     # Halt instruction
