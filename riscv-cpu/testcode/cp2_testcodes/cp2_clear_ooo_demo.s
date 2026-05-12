.section .text
.globl _start

# ============================================================================
# CP2 Clear Out-of-Order Demonstration Test
# This test is designed to make OOO behavior OBVIOUS and measurable
# Long-latency operations followed by independent short operations
# ============================================================================

_start:
    # ========================================================================
    # Initialize test values
    # ========================================================================
    addi x10, x0, 100       # x10 = 100
    addi x11, x0, 200       # x11 = 200
    addi x12, x0, 10        # x12 = 10
    addi x13, x0, 20        # x13 = 20
    addi x14, x0, 5         # x14 = 5
    addi x15, x0, 7         # x15 = 7
    
    # Add NOPs to ensure initialization completes
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 1: Single long multiply followed by independent adds
    # Expected: The adds complete before the multiply
    # ========================================================================
    
    mul  x1, x10, x11       # x1 = 20000 (LONG - should complete LAST)
    
    # These should all complete BEFORE the multiply above
    add  x2, x12, x13       # x2 = 30 (should complete early)
    add  x3, x13, x14       # x3 = 25 (should complete early)
    add  x4, x14, x15       # x4 = 12 (should complete early)
    add  x5, x12, x15       # x5 = 17 (should complete early)
    xor  x6, x12, x13       # x6 = 30 (should complete early)
    or   x7, x14, x15       # x7 = 7 (should complete early)
    and  x8, x12, x13       # x8 = 0 (should complete early)
    
    # This depends on multiply result - MUST wait for multiply
    add  x9, x1, x2         # x9 = 20030 (depends on x1, must wait)
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 2: Single long divide followed by independent operations
    # Expected: Independent ops complete before divide
    # ========================================================================
    
    div  x16, x10, x14      # x16 = 20 (LONG - should complete LAST)
    
    # Independent operations
    slli x17, x12, 2        # x17 = 40 (should complete early)
    srli x18, x11, 1        # x18 = 100 (should complete early)
    andi x19, x10, 0xFF     # x19 = 100 (should complete early)
    ori  x20, x14, 0x10     # x20 = 21 (should complete early)
    xori x21, x15, 0x0F     # x21 = 8 (should complete early)
    
    # Depends on divide result
    add  x22, x16, x17      # x22 = 60 (depends on x16, must wait)
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 3: Multiple long operations with independent ops between
    # Expected: Independent ops execute while long ops are in flight
    # ========================================================================
    
    mul  x23, x10, x11      # x23 = 20000 (LONG)
    div  x24, x11, x14      # x24 = 40 (LONG)
    mul  x25, x12, x13      # x25 = 200 (LONG)
    
    # These execute while long ops are computing
    add  x26, x14, x15      # x26 = 12 (INDEPENDENT)
    sub  x27, x13, x12      # x27 = 10 (INDEPENDENT)
    xor  x28, x14, x15      # x28 = 2 (INDEPENDENT)
    sll  x29, x12, x14      # x29 = 320 (INDEPENDENT, shift by 5)
    
    # These depend on long ops - must wait
    add  x30, x23, x24      # x30 = 20040 (depends on x23, x24)
    add  x31, x25, x26      # x31 = 212 (depends on x25)
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 4: Waterfall of long operations with short ops
    # Expected: Short ops weave between long ops
    # ========================================================================
    
    addi x1, x0, 50
    addi x2, x0, 25
    addi x3, x0, 3
    
    mul  x4, x1, x2         # x4 = 1250 (LONG 1)
    add  x5, x1, x2         # x5 = 75 (SHORT 1)
    
    div  x6, x1, x3         # x6 = 16 (LONG 2)
    sub  x7, x2, x3         # x7 = 22 (SHORT 2)
    
    mul  x8, x2, x3         # x8 = 75 (LONG 3)
    and  x9, x1, x2         # x9 = 16 (SHORT 3)
    
    div  x10, x4, x3        # x10 = 416 (LONG 4, depends on LONG 1)
    or   x11, x1, x3        # x11 = 51 (SHORT 4)
    
    # Final accumulation
    add  x12, x4, x5        # x12 = 1325 (depends on LONG 1, SHORT 1)
    add  x13, x6, x7        # x13 = 38 (depends on LONG 2, SHORT 2)
    add  x14, x8, x9        # x14 = 91 (depends on LONG 3, SHORT 3)
    add  x15, x10, x11      # x15 = 467 (depends on LONG 4, SHORT 4)
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 5: Three independent multiply chains
    # Expected: All three chains execute in parallel
    # ========================================================================
    
    # Chain A: mul -> add -> mul
    addi x1, x0, 6
    addi x2, x0, 7
    mul  x3, x1, x2         # x3 = 42 (LONG A1)
    add  x4, x3, x1         # x4 = 48 (depends on A1)
    mul  x5, x4, x2         # x5 = 336 (LONG A2, depends on A1 result)
    
    # Chain B: independent operations
    addi x10, x0, 11
    addi x11, x0, 13
    mul  x12, x10, x11      # x12 = 143 (LONG B1, INDEPENDENT of A)
    add  x13, x12, x10      # x13 = 154 (depends on B1)
    mul  x14, x13, x11      # x14 = 2002 (LONG B2, depends on B1 result)
    
    # Chain C: more independent operations
    addi x20, x0, 17
    addi x21, x0, 19
    mul  x22, x20, x21      # x22 = 323 (LONG C1, INDEPENDENT of A & B)
    add  x23, x22, x20      # x23 = 340 (depends on C1)
    mul  x24, x23, x21      # x24 = 6460 (LONG C2, depends on C1 result)
    
    # Merge all chains (must wait for all to complete)
    add  x30, x5, x14       # x30 = 2338 (depends on A & B)
    add  x31, x30, x24      # x31 = 8798 (depends on all chains)
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 6: Maximum independent operations after one long operation
    # Expected: All independent ops complete while long op executes
    # ========================================================================
    
    addi x1, x0, 123
    addi x2, x0, 456
    
    mul  x3, x1, x2         # x3 = 56088 (ONE LONG OP)
    
    # 20 independent short operations (all should complete before mul)
    addi x4, x0, 1
    addi x5, x0, 2
    addi x6, x0, 3
    addi x7, x0, 4
    addi x8, x0, 5
    addi x9, x0, 6
    addi x10, x0, 7
    addi x11, x0, 8
    addi x12, x0, 9
    addi x13, x0, 10
    
    add  x14, x4, x5        # x14 = 3
    add  x15, x6, x7        # x15 = 7
    add  x16, x8, x9        # x16 = 11
    add  x17, x10, x11      # x17 = 15
    add  x18, x12, x13      # x18 = 19
    
    xor  x19, x4, x5        # x19 = 3
    xor  x20, x6, x7        # x20 = 7
    xor  x21, x8, x9        # x21 = 15
    xor  x22, x10, x11      # x22 = 15
    xor  x23, x12, x13      # x23 = 7
    
    # Now use the multiply result
    add  x24, x3, x14       # x24 = 56091 (depends on mul)
    
    # ========================================================================
    # TEST 7: Back-to-back dependent multiplies (forwarding test)
    # Expected: Each mul must wait for previous, but other ops can slip in
    # ========================================================================
    
    addi x1, x0, 2
    addi x10, x0, 100       # Independent value
    
    mul  x2, x1, x1         # x2 = 4 (LONG 1)
    add  x11, x10, x10      # x11 = 200 (INDEPENDENT, should slip in)
    
    mul  x3, x2, x2         # x3 = 16 (LONG 2, depends on LONG 1)
    add  x12, x11, x10      # x12 = 300 (INDEPENDENT, should slip in)
    
    mul  x4, x3, x3         # x4 = 256 (LONG 3, depends on LONG 2)
    add  x13, x12, x10      # x13 = 400 (INDEPENDENT, should slip in)
    
    mul  x5, x4, x1         # x5 = 512 (LONG 4, depends on LONG 3)
    add  x14, x13, x10      # x14 = 500 (INDEPENDENT, should slip in)
    
    # ========================================================================
    # TEST 8: Complex dependency diamond with long operations
    # ========================================================================
    
    addi x1, x0, 20
    addi x2, x0, 30
    addi x3, x0, 5
    
    # Two independent long ops at the top
    mul  x4, x1, x2         # x4 = 600 (LONG A)
    div  x5, x2, x3         # x5 = 6 (LONG B)
    
    # Independent short ops
    add  x10, x1, x3        # x10 = 25 (INDEPENDENT)
    sub  x11, x2, x3        # x11 = 25 (INDEPENDENT)
    
    # Converge the diamond (depends on both long ops)
    add  x6, x4, x5         # x6 = 606 (depends on A & B)
    mul  x7, x6, x3         # x7 = 3030 (LONG C, depends on convergence)
    
    # Another independent stream
    xor  x12, x10, x11      # x12 = 0 (INDEPENDENT)
    or   x13, x10, x11      # x13 = 25 (INDEPENDENT)
    
    # Final result
    add  x8, x7, x12        # x8 = 3030 (depends on LONG C)

    # ========================================================================
    # HALT - Use slti x0, x0, -256 to signal end
    # ========================================================================
halt:
    slti x0, x0, -256
