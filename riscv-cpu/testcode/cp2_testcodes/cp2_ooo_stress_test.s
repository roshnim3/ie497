.section .text
.globl _start

# ============================================================================
# CP2 Out-of-Order Stress Test
# Specifically designed to stress OOO execution with:
# - Multiple long-latency ops (mul/div) interspersed with short ops
# - Complex dependency chains
# - Independent instruction streams
# ============================================================================

_start:
    # ========================================================================
    # Test 1: Multiple independent mul/div operations with intervening ALU ops
    # Purpose: Verify multiple long-latency ops can be in flight simultaneously
    # ========================================================================
    
    # Set up operands
    addi x1, x0, 100
    addi x2, x0, 7
    addi x3, x0, 50
    addi x4, x0, 3
    addi x5, x0, 200
    addi x6, x0, 11
    
    # Start multiple long-latency operations
    mul  x10, x1, x2        # x10 = 700 (LONG)
    div  x11, x1, x2        # x11 = 14 (LONG)
    mul  x12, x3, x4        # x12 = 150 (LONG)
    div  x13, x3, x4        # x13 = 16 (LONG)
    mul  x14, x5, x6        # x14 = 2200 (LONG)
    div  x15, x5, x6        # x15 = 18 (LONG)
    
    # These independent ALU ops should complete before mul/div
    addi x20, x0, 10
    addi x21, x0, 20
    addi x22, x0, 30
    add  x23, x20, x21      # x23 = 30
    sub  x24, x22, x20      # x24 = 20
    xor  x25, x23, x24      # x25 = 10
    or   x26, x23, x24      # x26 = 30
    and  x27, x23, x24      # x27 = 20
    slli x28, x20, 2        # x28 = 40
    srli x29, x22, 1        # x29 = 15
    
    # Now use mul/div results (these must wait)
    add  x30, x10, x11      # x30 = 714 (depends on x10, x11)
    add  x31, x12, x13      # x31 = 166 (depends on x12, x13)
    
    # ========================================================================
    # Test 2: Dependent chain of mul/div operations
    # Purpose: Test forwarding from one long-latency op to another
    # ========================================================================
    
    addi x1, x0, 24
    addi x2, x0, 4
    
    mul  x3, x1, x2         # x3 = 96
    div  x4, x3, x2         # x4 = 24 (depends on x3)
    mul  x5, x4, x2         # x5 = 96 (depends on x4)
    div  x6, x5, x1         # x6 = 4 (depends on x5)
    
    # ========================================================================
    # Test 3: Diamond dependency pattern
    # Purpose: Test when multiple paths converge
    # ========================================================================
    
    addi x10, x0, 12
    addi x11, x0, 3
    
    mul  x12, x10, x11      # x12 = 36 (path A)
    div  x13, x10, x11      # x13 = 4 (path B)
    
    # Both paths converge here
    add  x14, x12, x13      # x14 = 40 (depends on both paths)
    mul  x15, x12, x13      # x15 = 144 (depends on both paths)
    
    # ========================================================================
    # Test 4: Interleaved independent and dependent operations
    # Purpose: Maximum OOO opportunity
    # ========================================================================
    
    # Initialize registers
    addi x1, x0, 5
    addi x2, x0, 7
    addi x3, x0, 11
    addi x4, x0, 13
    
    # Stream A: dependent chain (mul -> add -> mul)
    mul  x5, x1, x2         # x5 = 35 (A1)
    add  x6, x5, x3         # x6 = 46 (A2, depends on A1)
    mul  x7, x6, x4         # x7 = 598 (A3, depends on A2)
    
    # Stream B: independent operations
    add  x10, x3, x4        # x10 = 24 (B1, independent)
    sub  x11, x4, x3        # x11 = 2 (B2, independent)
    xor  x12, x3, x4        # x12 = 6 (B3, independent)
    
    # Stream C: another dependent chain
    div  x15, x3, x1        # x15 = 2 (C1)
    add  x16, x15, x1       # x16 = 7 (C2, depends on C1)
    mul  x17, x16, x2       # x17 = 49 (C3, depends on C2)
    
    # Merge all streams
    add  x20, x7, x12       # x20 = 604 (uses A and B)
    add  x21, x17, x11      # x21 = 51 (uses C and B)
    add  x22, x20, x21      # x22 = 655 (uses all)
    
    # ========================================================================
    # Test 5: Register pressure with many live values
    # Purpose: Stress register renaming
    # ========================================================================
    
    # Create many live values simultaneously
    addi x1, x0, 1
    addi x2, x0, 2
    addi x3, x0, 3
    addi x4, x0, 4
    addi x5, x0, 5
    addi x6, x0, 6
    addi x7, x0, 7
    addi x8, x0, 8
    
    # All of these can execute in parallel
    mul  x10, x1, x2        # x10 = 2
    mul  x11, x3, x4        # x11 = 12
    mul  x12, x5, x6        # x12 = 30
    mul  x13, x7, x8        # x13 = 56
    
    # Independent adds
    add  x14, x1, x2        # x14 = 3
    add  x15, x3, x4        # x15 = 7
    add  x16, x5, x6        # x16 = 11
    add  x17, x7, x8        # x17 = 15
    
    # Now use all these values
    add  x20, x10, x11      # x20 = 14
    add  x21, x12, x13      # x21 = 86
    add  x22, x14, x15      # x22 = 10
    add  x23, x16, x17      # x23 = 26
    
    add  x24, x20, x21      # x24 = 100
    add  x25, x22, x23      # x25 = 36
    add  x26, x24, x25      # x26 = 136
    
    # ========================================================================
    # Test 6: Rapid fire mul/div to same destination (WAW hazards)
    # Purpose: Test correct ordering of writes to same register
    # ========================================================================
    
    addi x1, x0, 10
    addi x2, x0, 5
    
    # All write to x3, but only last one should be visible
    mul  x3, x1, x2         # x3 = 50 (will be overwritten)
    div  x3, x1, x2         # x3 = 2 (will be overwritten)
    add  x3, x1, x2         # x3 = 15 (will be overwritten)
    sub  x3, x1, x2         # x3 = 5 (FINAL VALUE)
    
    # Use x3 - should get final value (5)
    mul  x4, x3, x2         # x4 = 25
    
    # ========================================================================
    # Test 7: Many independent divides (stress divide unit)
    # Purpose: Fill divide pipeline/queue
    # ========================================================================
    
    addi x1, x0, 100
    addi x2, x0, 200
    addi x3, x0, 300
    addi x4, x0, 400
    
    addi x10, x0, 7
    addi x11, x0, 11
    addi x12, x0, 13
    addi x13, x0, 17
    
    div  x5, x1, x10        # x5 = 14
    div  x6, x2, x11        # x6 = 18
    div  x7, x3, x12        # x7 = 23
    div  x8, x4, x13        # x8 = 23
    
    # Use all results
    add  x14, x5, x6        # x14 = 32
    add  x15, x7, x8        # x15 = 46
    add  x16, x14, x15      # x16 = 78
    
    # ========================================================================
    # Test 8: Back-to-back dependent multiplies
    # Purpose: Test mul-to-mul forwarding
    # ========================================================================
    
    addi x1, x0, 2
    mul  x2, x1, x1         # x2 = 4
    mul  x3, x2, x2         # x3 = 16 (depends on x2)
    mul  x4, x3, x3         # x4 = 256 (depends on x3)
    mul  x5, x4, x1         # x5 = 512 (depends on x4)
    
    # ========================================================================
    # Test 9: Mix all instruction types with complex dependencies
    # Purpose: Ultimate OOO stress test
    # ========================================================================
    
    addi x10, x0, 20
    addi x11, x0, 4
    addi x12, x0, 3
    
    # Start long ops
    mul  x13, x10, x11      # x13 = 80 (L1)
    div  x14, x10, x11      # x14 = 5 (L2)
    
    # Short ops while waiting
    slli x15, x11, 2        # x15 = 16 (S1)
    srli x16, x10, 1        # x16 = 10 (S2)
    andi x17, x10, 0x0F     # x17 = 4 (S3)
    ori  x18, x11, 0x10     # x18 = 20 (S4)
    
    # Use long op results
    add  x19, x13, x14      # x19 = 85 (depends on L1, L2)
    
    # Another long op depending on short ops
    mul  x20, x15, x16      # x20 = 160 (depends on S1, S2)
    
    # Final convergence
    add  x21, x19, x20      # x21 = 245
    div  x22, x21, x12      # x22 = 81
    
    # ========================================================================
    # Test 10: Zero operand special cases mixed with normal ops
    # ========================================================================
    
    addi x1, x0, 42
    addi x2, x0, 7
    
    mul  x3, x1, x0         # x3 = 0 (mul by zero)
    div  x4, x1, x0         # x4 = -1 (div by zero)
    add  x5, x3, x1         # x5 = 42 (use mul result)
    add  x6, x4, x1         # x6 = 41 (use div result)
    
    rem  x7, x1, x0         # x7 = 42 (rem by zero)
    divu x8, x1, x0         # x8 = 0xFFFFFFFF (divu by zero)

    # ========================================================================
    # HALT
    # ========================================================================
halt:
    slti x0, x0, -256
