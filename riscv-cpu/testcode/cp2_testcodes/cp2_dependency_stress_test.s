.section .text
.globl _start

# ============================================================================
# CP2 DEPENDENCY STRESS TEST
# Exhaustively tests RAW, WAR, WAW hazards with complex patterns
# ============================================================================

_start:
    # ========================================================================
    # TEST 1: LONG RAW DEPENDENCY CHAIN (Read-After-Write)
    # Single register updated repeatedly - tests forwarding through many stages
    # ========================================================================
    
    addi x1, x0, 1
    
    # 20-stage dependency chain on x1
    add  x1, x1, x1         # x1 = 2
    add  x1, x1, x1         # x1 = 4
    add  x1, x1, x1         # x1 = 8
    add  x1, x1, x1         # x1 = 16
    add  x1, x1, x1         # x1 = 32
    add  x1, x1, x1         # x1 = 64
    add  x1, x1, x1         # x1 = 128
    add  x1, x1, x1         # x1 = 256
    add  x1, x1, x1         # x1 = 512
    add  x1, x1, x1         # x1 = 1024
    add  x1, x1, x1         # x1 = 2048
    add  x1, x1, x1         # x1 = 4096
    add  x1, x1, x1         # x1 = 8192
    add  x1, x1, x1         # x1 = 16384
    add  x1, x1, x1         # x1 = 32768
    
    # Use final value
    add  x2, x1, x0         # x2 = 32768
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 2: MULTIPLE PARALLEL RAW CHAINS
    # Several independent dependency chains executing simultaneously
    # ========================================================================
    
    # Chain A on x3
    addi x3, x0, 1
    add  x3, x3, x3         # x3 = 2
    add  x3, x3, x3         # x3 = 4
    add  x3, x3, x3         # x3 = 8
    add  x3, x3, x3         # x3 = 16
    add  x3, x3, x3         # x3 = 32
    
    # Chain B on x4
    addi x4, x0, 10
    add  x4, x4, x4         # x4 = 20
    add  x4, x4, x4         # x4 = 40
    add  x4, x4, x4         # x4 = 80
    add  x4, x4, x4         # x4 = 160
    add  x4, x4, x4         # x4 = 320
    
    # Chain C on x5
    addi x5, x0, 3
    mul  x5, x5, x5         # x5 = 9
    mul  x5, x5, x5         # x5 = 81
    mul  x5, x5, x5         # x5 = 6561
    
    # Merge chains
    add  x6, x3, x4         # x6 = 352 (depends on A & B)
    add  x7, x6, x5         # x7 = 6913 (depends on merge & C)
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 3: WAW HAZARD (Write-After-Write)
    # Multiple instructions write to same destination - only last should be visible
    # ========================================================================
    
    addi x10, x0, 1
    addi x11, x0, 2
    addi x12, x0, 3
    addi x13, x0, 4
    
    # All write to x8, but only last value should persist
    add  x8, x10, x11       # x8 = 3 (will be overwritten)
    sub  x8, x12, x11       # x8 = 1 (will be overwritten)
    mul  x8, x10, x13       # x8 = 4 (will be overwritten)
    div  x8, x13, x11       # x8 = 2 (will be overwritten)
    xor  x8, x12, x11       # x8 = 1 (will be overwritten)
    add  x8, x13, x13       # x8 = 8 (FINAL VALUE)
    
    # Use x8 - should see only final value (8)
    mul  x9, x8, x11        # x9 = 16
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 4: COMPLEX RAW WITH MULTIPLE SOURCES
    # Instructions depend on multiple previous results
    # ========================================================================
    
    addi x1, x0, 10
    addi x2, x0, 20
    addi x3, x0, 30
    
    # Create initial values with dependencies
    mul  x4, x1, x2         # x4 = 200 (depends on x1, x2)
    mul  x5, x2, x3         # x5 = 600 (depends on x2, x3)
    mul  x6, x1, x3         # x6 = 300 (depends on x1, x3)
    
    # Second level - depend on first level
    add  x7, x4, x5         # x7 = 800 (depends on x4, x5)
    add  x8, x5, x6         # x8 = 900 (depends on x5, x6)
    add  x9, x4, x6         # x9 = 500 (depends on x4, x6)
    
    # Third level - depend on second level
    mul  x10, x7, x8        # x10 = 720000 (depends on x7, x8)
    mul  x11, x8, x9        # x11 = 450000 (depends on x8, x9)
    mul  x12, x7, x9        # x12 = 400000 (depends on x7, x9)
    
    # Fourth level - converge all paths
    add  x13, x10, x11      # x13 = 1170000 (depends on x10, x11)
    add  x14, x13, x12      # x14 = 1570000 (depends on x13, x12)
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 5: ALTERNATING LONG AND SHORT LATENCY WITH DEPENDENCIES
    # Mix mul/div (long) with alu (short) in dependency chain
    # ========================================================================
    
    addi x1, x0, 100
    addi x2, x0, 5
    
    mul  x3, x1, x2         # x3 = 500 (LONG)
    add  x4, x3, x1         # x4 = 600 (SHORT, depends on LONG)
    div  x5, x4, x2         # x5 = 120 (LONG, depends on SHORT)
    sub  x6, x5, x2         # x6 = 115 (SHORT, depends on LONG)
    mul  x7, x6, x2         # x7 = 575 (LONG, depends on SHORT)
    add  x8, x7, x1         # x8 = 675 (SHORT, depends on LONG)
    div  x9, x8, x2         # x9 = 135 (LONG, depends on SHORT)
    xor  x10, x9, x1        # x10 = 235 (SHORT, depends on LONG)
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 6: DIAMOND DEPENDENCY PATTERN
    # Single source splits into multiple paths, then reconverges
    # ========================================================================
    
    addi x1, x0, 42
    
    # Split: x1 -> x2, x3, x4 (three parallel paths)
    mul  x2, x1, x1         # Path A: x2 = 1764
    add  x3, x1, x1         # Path B: x3 = 84
    sub  x4, x1, x0         # Path C: x4 = 42
    
    # Process each path
    div  x5, x2, x1         # Path A continues: x5 = 42
    mul  x6, x3, x1         # Path B continues: x6 = 3528
    add  x7, x4, x4         # Path C continues: x7 = 84
    
    # Partial reconvergence: A+B, B+C
    add  x8, x5, x6         # x8 = 3570 (A + B)
    add  x9, x6, x7         # x9 = 3612 (B + C)
    
    # Full reconvergence: combine all
    add  x10, x8, x9        # x10 = 7182 (all paths)
    add  x11, x10, x7       # x11 = 7266 (include C again)
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 7: CASCADING WAW HAZARDS WITH DEPENDENCIES
    # Multiple WAW hazards where later writes depend on earlier computations
    # ========================================================================
    
    addi x1, x0, 5
    addi x2, x0, 10
    
    # First set of writes to x3
    add  x3, x1, x2         # x3 = 15 (version 1)
    mul  x4, x3, x2         # x4 = 150 (uses version 1)
    sub  x3, x2, x1         # x3 = 5 (version 2, overwrites)
    div  x5, x3, x1         # x5 = 1 (uses version 2)
    mul  x3, x1, x2         # x3 = 50 (version 3, overwrites)
    add  x6, x3, x1         # x6 = 55 (uses version 3)
    
    # Should see: x4=150, x5=1, x6=55, x3=50
    add  x7, x4, x5         # x7 = 151
    add  x8, x7, x6         # x8 = 206
    add  x9, x8, x3         # x9 = 256
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 8: TREE DEPENDENCY PATTERN
    # Build a binary tree of dependencies
    # ========================================================================
    
    # Level 0 (leaves)
    addi x1, x0, 1
    addi x2, x0, 2
    addi x3, x0, 3
    addi x4, x0, 4
    addi x5, x0, 5
    addi x6, x0, 6
    addi x7, x0, 7
    addi x8, x0, 8
    
    # Level 1 (combine pairs)
    add  x9, x1, x2         # x9 = 3
    add  x10, x3, x4        # x10 = 7
    add  x11, x5, x6        # x11 = 11
    add  x12, x7, x8        # x12 = 15
    
    # Level 2 (combine pairs of pairs)
    mul  x13, x9, x10       # x13 = 21
    mul  x14, x11, x12      # x14 = 165
    
    # Level 3 (root - combine all)
    add  x15, x13, x14      # x15 = 186
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 9: CIRCULAR-LIKE DEPENDENCIES (not truly circular, but complex)
    # Complex dependency web where multiple registers reference each other
    # ========================================================================
    
    addi x1, x0, 10
    addi x2, x0, 20
    addi x3, x0, 30
    
    add  x4, x1, x2         # x4 = 30 (uses x1, x2)
    add  x5, x2, x3         # x5 = 50 (uses x2, x3)
    add  x6, x3, x1         # x6 = 40 (uses x3, x1)
    
    add  x7, x4, x5         # x7 = 80 (uses x4, x5)
    add  x8, x5, x6         # x8 = 90 (uses x5, x6)
    add  x9, x6, x4         # x9 = 70 (uses x6, x4)
    
    add  x10, x7, x8        # x10 = 170 (uses x7, x8)
    add  x11, x8, x9        # x11 = 160 (uses x8, x9)
    add  x12, x9, x7        # x12 = 150 (uses x9, x7)
    
    add  x13, x10, x11      # x13 = 330
    add  x14, x11, x12      # x14 = 310
    add  x15, x12, x10      # x15 = 320
    
    add  x16, x13, x14      # x16 = 640
    add  x17, x14, x15      # x17 = 630
    add  x18, x13, x15      # x18 = 650
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 10: DEPENDENT CHAIN WITH ALL OPERATION TYPES
    # Long chain using different instruction types at each stage
    # ========================================================================
    
    addi x1, x0, 100
    addi x2, x0, 7
    
    mul  x3, x1, x2         # x3 = 700 (MUL)
    div  x4, x3, x2         # x4 = 100 (DIV, depends on MUL)
    add  x5, x4, x1         # x5 = 200 (ADD, depends on DIV)
    sub  x6, x5, x2         # x6 = 193 (SUB, depends on ADD)
    xor  x7, x6, x1         # x7 = 165 (XOR, depends on SUB)
    and  x8, x7, x5         # x8 = 160 (AND, depends on XOR and ADD)
    or   x9, x8, x2         # x9 = 167 (OR, depends on AND)
    sll  x10, x9, x2        # x10 = 21376 (SLL, depends on OR)
    srl  x11, x10, x2       # x11 = 167 (SRL, depends on SLL)
    mul  x12, x11, x2       # x12 = 1169 (MUL, depends on SRL)
    div  x13, x12, x2       # x13 = 167 (DIV, depends on MUL)
    rem  x14, x13, x2       # x14 = 6 (REM, depends on DIV)
    mulh x15, x13, x1       # x15 = 0 (MULH, depends on DIV)
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 11: REGISTER REUSE WITH DEPENDENCIES
    # Same register used as source and dest with dependencies
    # ========================================================================
    
    addi x1, x0, 10
    addi x2, x0, 20
    
    # x3 is both source and destination repeatedly
    add  x3, x1, x2         # x3 = 30
    add  x3, x3, x1         # x3 = 40 (reads old x3, writes new x3)
    add  x3, x3, x2         # x3 = 60 (reads old x3, writes new x3)
    mul  x3, x3, x1         # x3 = 600 (reads old x3, writes new x3)
    div  x3, x3, x2         # x3 = 30 (reads old x3, writes new x3)
    sub  x3, x3, x1         # x3 = 20 (reads old x3, writes new x3)
    
    # Same with x4
    mul  x4, x1, x2         # x4 = 200
    mul  x4, x4, x4         # x4 = 40000
    div  x4, x4, x1         # x4 = 4000
    div  x4, x4, x2         # x4 = 200
    
    # Combine
    add  x5, x3, x4         # x5 = 220
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 12: MAXIMUM DEPENDENCY DEPTH
    # 32 stages of dependencies (extremely long chain)
    # ========================================================================
    
    addi x1, x0, 1
    
    add  x1, x1, x1         # Stage 1: x1 = 2
    add  x1, x1, x1         # Stage 2: x1 = 4
    add  x1, x1, x1         # Stage 3: x1 = 8
    add  x1, x1, x1         # Stage 4: x1 = 16
    add  x1, x1, x1         # Stage 5: x1 = 32
    add  x1, x1, x1         # Stage 6: x1 = 64
    add  x1, x1, x1         # Stage 7: x1 = 128
    add  x1, x1, x1         # Stage 8: x1 = 256
    add  x1, x1, x1         # Stage 9: x1 = 512
    add  x1, x1, x1         # Stage 10: x1 = 1024
    add  x1, x1, x1         # Stage 11: x1 = 2048
    add  x1, x1, x1         # Stage 12: x1 = 4096
    add  x1, x1, x1         # Stage 13: x1 = 8192
    add  x1, x1, x1         # Stage 14: x1 = 16384
    add  x1, x1, x1         # Stage 15: x1 = 32768
    add  x1, x1, x1         # Stage 16: x1 = 65536
    add  x1, x1, x1         # Stage 17: x1 = 131072
    add  x1, x1, x1         # Stage 18: x1 = 262144
    add  x1, x1, x1         # Stage 19: x1 = 524288
    add  x1, x1, x1         # Stage 20: x1 = 1048576
    add  x1, x1, x1         # Stage 21: x1 = 2097152
    add  x1, x1, x1         # Stage 22: x1 = 4194304
    add  x1, x1, x1         # Stage 23: x1 = 8388608
    add  x1, x1, x1         # Stage 24: x1 = 16777216
    add  x1, x1, x1         # Stage 25: x1 = 33554432
    add  x1, x1, x1         # Stage 26: x1 = 67108864
    add  x1, x1, x1         # Stage 27: x1 = 134217728
    add  x1, x1, x1         # Stage 28: x1 = 268435456
    add  x1, x1, x1         # Stage 29: x1 = 536870912
    add  x1, x1, x1         # Stage 30: x1 = 1073741824
    add  x1, x1, x1         # Stage 31: x1 = 2147483648 (0x80000000)
    add  x1, x1, x1         # Stage 32: x1 = 0 (overflow)
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 13: CROSS-FUNCTIONAL-UNIT DEPENDENCIES
    # Dependencies that cross between MUL, DIV, and ALU units
    # ========================================================================
    
    addi x1, x0, 100
    addi x2, x0, 10
    addi x3, x0, 5
    
    # MUL -> ALU -> DIV -> ALU -> MUL
    mul  x4, x1, x2         # x4 = 1000 (MUL unit)
    add  x5, x4, x3         # x5 = 1005 (ALU unit, depends on MUL)
    div  x6, x5, x2         # x6 = 100 (DIV unit, depends on ALU)
    sub  x7, x6, x3         # x7 = 95 (ALU unit, depends on DIV)
    mul  x8, x7, x2         # x8 = 950 (MUL unit, depends on ALU)
    
    # DIV -> MUL -> ALU -> DIV
    div  x9, x1, x3         # x9 = 20 (DIV unit)
    mul  x10, x9, x2        # x10 = 200 (MUL unit, depends on DIV)
    xor  x11, x10, x1       # x11 = 156 (ALU unit, depends on MUL)
    div  x12, x11, x3       # x12 = 31 (DIV unit, depends on ALU)
    
    # Converge
    add  x13, x8, x12       # x13 = 981
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 14: DEPENDENCIES WITH STRUCTURAL HAZARDS
    # Issue dependent operations when RS/ROB might be full
    # ========================================================================
    
    addi x1, x0, 7
    addi x2, x0, 11
    addi x3, x0, 13
    
    # Fill resources with independent ops
    mul  x4, x1, x2
    mul  x5, x2, x3
    mul  x6, x3, x1
    mul  x7, x1, x1
    mul  x8, x2, x2
    mul  x9, x3, x3
    
    # Now issue dependent chain while resources full
    mul  x10, x4, x5        # Depends on first two muls
    mul  x11, x10, x6       # Depends on x10
    mul  x12, x11, x7       # Depends on x11
    mul  x13, x12, x8       # Depends on x12
    
    nop
    nop
    nop

    # ========================================================================
    # HALT
    # ========================================================================
halt:
    slti x0, x0, -256
