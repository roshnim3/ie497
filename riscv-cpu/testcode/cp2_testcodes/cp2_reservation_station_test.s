.section .text
.globl _start

# ============================================================================
# CP2 Reservation Station Fill Test
# Explicitly designed to FILL all reservation stations and test queueing
# ============================================================================

_start:
    # ========================================================================
    # Initialize operands
    # ========================================================================
    addi x1, x0, 100
    addi x2, x0, 200
    addi x3, x0, 300
    addi x4, x0, 400
    addi x5, x0, 500
    addi x6, x0, 600
    addi x7, x0, 700
    addi x8, x0, 800
    addi x9, x0, 900
    addi x10, x0, 1000
    addi x11, x0, 7
    addi x12, x0, 11
    addi x13, x0, 13
    addi x14, x0, 17
    addi x15, x0, 19
    
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 1: FILL MULTIPLY RESERVATION STATIONS (8 entries deep)
    # Issue many multiply operations back-to-back to fill all 8 MUL RS entries
    # These are all INDEPENDENT - they should all be issued to RS
    # ========================================================================
    
    # RS has 8 slots - issue exactly 8 to fill all slots
    mul  x16, x1, x2        # MUL RS Entry 1/8
    mul  x17, x3, x4        # MUL RS Entry 2/8
    mul  x18, x5, x6        # MUL RS Entry 3/8
    mul  x19, x7, x8        # MUL RS Entry 4/8
    mul  x20, x9, x10       # MUL RS Entry 5/8
    mul  x21, x1, x3        # MUL RS Entry 6/8
    mul  x22, x2, x4        # MUL RS Entry 7/8
    mul  x23, x5, x7        # MUL RS Entry 8/8 (RS NOW FULL)
    
    # Issue more to test queueing/backpressure (beyond 8 slots)
    mul  x24, x6, x8        # Should queue or stall (RS full)
    mul  x25, x9, x1        # Should queue or stall
    mul  x26, x10, x2       # Should queue or stall
    mul  x27, x3, x5        # Should queue or stall
    mul  x28, x4, x6        # Should queue or stall
    mul  x29, x7, x9        # Should queue or stall
    mul  x30, x8, x10       # Should queue or stall
    mul  x31, x1, x2        # Should queue or stall
    
    # All 16 multiplies should eventually complete
    # Use one result to verify completion
    add  x1, x16, x17       # Wait for first two to complete
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 2: FILL DIVIDE RESERVATION STATIONS (8 entries deep)
    # Issue many divide operations to fill all 8 DIV RS entries
    # ========================================================================
    
    # Reset operands
    addi x1, x0, 1000
    addi x2, x0, 2000
    addi x3, x0, 300
    addi x4, x0, 400
    addi x5, x0, 500
    addi x6, x0, 600
    addi x7, x0, 700
    addi x8, x0, 800
    
    # Issue exactly 8 independent divides to fill all RS slots
    div  x9, x1, x11        # DIV RS Entry 1/8
    div  x10, x2, x12       # DIV RS Entry 2/8
    div  x16, x3, x13       # DIV RS Entry 3/8
    div  x17, x4, x14       # DIV RS Entry 4/8
    div  x18, x5, x15       # DIV RS Entry 5/8
    div  x19, x6, x11       # DIV RS Entry 6/8
    div  x20, x7, x12       # DIV RS Entry 7/8
    div  x21, x8, x13       # DIV RS Entry 8/8 (RS NOW FULL)
    
    # Issue more to test queueing/backpressure (beyond 8 slots)
    div  x22, x1, x14       # Should queue or stall (RS full)
    div  x23, x2, x15       # Should queue or stall
    div  x24, x3, x11       # Should queue or stall
    div  x25, x4, x12       # Should queue or stall
    div  x26, x5, x13       # Should queue or stall
    div  x27, x6, x14       # Should queue or stall
    div  x28, x7, x15       # Should queue or stall
    div  x29, x8, x11       # Should queue or stall
    
    # Use results
    add  x30, x9, x10       # Wait for completion
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 3: FILL ALU RESERVATION STATIONS (8 entries deep)
    # Issue many ALU operations to fill all 8 ALU RS entries
    # ========================================================================
    
    addi x1, x0, 10
    addi x2, x0, 20
    addi x3, x0, 30
    addi x4, x0, 40
    addi x5, x0, 50
    addi x6, x0, 60
    addi x7, x0, 70
    addi x8, x0, 80
    
    # Issue exactly 8 independent ALU operations to fill all RS slots
    add  x9, x1, x2         # ALU RS Entry 1/8
    sub  x10, x3, x4        # ALU RS Entry 2/8
    xor  x11, x5, x6        # ALU RS Entry 3/8
    or   x12, x7, x8        # ALU RS Entry 4/8
    and  x13, x1, x3        # ALU RS Entry 5/8
    sll  x14, x2, x1        # ALU RS Entry 6/8
    srl  x15, x3, x2        # ALU RS Entry 7/8
    sra  x16, x4, x1        # ALU RS Entry 8/8 (RS NOW FULL)
    
    # Issue more to test queueing/backpressure (beyond 8 slots)
    slt  x17, x5, x6        # Should queue or stall (RS full)
    sltu x18, x7, x8        # Should queue or stall
    add  x19, x2, x3        # Should queue or stall
    sub  x20, x4, x5        # Should queue or stall
    xor  x21, x6, x7        # Should queue or stall
    or   x22, x8, x1        # Should queue or stall
    and  x23, x2, x4        # Should queue or stall
    sll  x24, x3, x1        # Should queue or stall
    srl  x25, x5, x2        # Should queue or stall
    sra  x26, x6, x1        # Should queue or stall
    slt  x27, x7, x8        # Should queue or stall
    sltu x28, x1, x2        # Should queue or stall
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 4: MIXED OPERATION RS FILL
    # Fill all RS types simultaneously with independent operations
    # ========================================================================
    
    addi x1, x0, 123
    addi x2, x0, 456
    addi x3, x0, 789
    addi x4, x0, 7
    addi x5, x0, 11
    
    # Issue MUL, DIV, and ALU ops all at once
    mul  x6, x1, x2         # MUL RS 1
    div  x7, x1, x4         # DIV RS 1
    add  x8, x1, x2         # ALU RS 1
    
    mul  x9, x2, x3         # MUL RS 2
    div  x10, x2, x5        # DIV RS 2
    sub  x11, x2, x3        # ALU RS 2
    
    mul  x12, x3, x1        # MUL RS 3
    div  x13, x3, x4        # DIV RS 3
    xor  x14, x3, x1        # ALU RS 3
    
    mul  x15, x1, x3        # MUL RS 4
    div  x16, x1, x5        # DIV RS 4
    or   x17, x1, x3        # ALU RS 4
    
    mul  x18, x2, x1        # MUL RS 5
    div  x19, x2, x4        # DIV RS 5
    and  x20, x2, x1        # ALU RS 5
    
    mul  x21, x3, x2        # MUL RS 6
    div  x22, x3, x5        # DIV RS 6
    sll  x23, x3, x4        # ALU RS 6
    
    mul  x24, x1, x2        # MUL RS 7
    div  x25, x1, x4        # DIV RS 7
    srl  x26, x1, x4        # ALU RS 7
    
    mul  x27, x2, x3        # MUL RS 8
    div  x28, x2, x5        # DIV RS 8
    slt  x29, x2, x3        # ALU RS 8
    
    # Should queue if RS are full
    mul  x30, x3, x1        # MUL RS 9+
    div  x31, x3, x4        # DIV RS 9+
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 5: RS FILL WITH LONG DEPENDENCY CHAIN
    # Fill RS while having a long dependency chain in flight
    # Tests RS management when some entries are waiting on dependencies
    # ========================================================================
    
    addi x1, x0, 2
    
    # Start a long dependent chain (these occupy RS but wait for each other)
    mul  x2, x1, x1         # x2 = 4 (LONG, takes RS slot)
    mul  x3, x2, x2         # x3 = 16 (waits for x2, takes RS slot)
    mul  x4, x3, x3         # x4 = 256 (waits for x3, takes RS slot)
    mul  x5, x4, x4         # x5 = 65536 (waits for x4, takes RS slot)
    mul  x6, x5, x1         # x6 = 131072 (waits for x5, takes RS slot)
    
    # Now issue many independent operations while chain is executing
    addi x10, x0, 100
    addi x11, x0, 200
    addi x12, x0, 300
    addi x13, x0, 400
    addi x14, x0, 500
    
    mul  x15, x10, x11      # Independent, should get RS if available
    mul  x16, x11, x12      # Independent
    mul  x17, x12, x13      # Independent
    mul  x18, x13, x14      # Independent
    mul  x19, x14, x10      # Independent
    mul  x20, x10, x12      # Independent
    mul  x21, x11, x13      # Independent
    mul  x22, x12, x14      # Independent
    
    # These should complete while waiting for the long chain
    add  x23, x10, x11      # Fast operation
    add  x24, x12, x13      # Fast operation
    
    # Final use of chain result
    add  x25, x6, x23       # Waits for entire chain
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 6: RS PRESSURE WITH RAPID ISSUE AND COMPLETION
    # Issue operations faster than they can complete to maintain RS pressure
    # ========================================================================
    
    addi x1, x0, 50
    addi x2, x0, 3
    addi x3, x0, 60
    addi x4, x0, 4
    addi x5, x0, 70
    addi x6, x0, 5
    
    # Rapid fire multiplies
    mul  x7, x1, x1
    mul  x8, x1, x1
    mul  x9, x1, x1
    mul  x10, x1, x1
    mul  x11, x1, x1
    mul  x12, x1, x1
    mul  x13, x1, x1
    mul  x14, x1, x1
    mul  x15, x1, x1
    mul  x16, x1, x1
    
    # Rapid fire divides
    div  x17, x3, x2
    div  x18, x3, x2
    div  x19, x3, x2
    div  x20, x3, x2
    div  x21, x3, x2
    div  x22, x3, x2
    div  x23, x3, x2
    div  x24, x3, x2
    
    # More multiplies to keep pressure
    mul  x25, x5, x5
    mul  x26, x5, x5
    mul  x27, x5, x5
    mul  x28, x5, x5
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 7: ALTERNATING DEPENDENT AND INDEPENDENT OPS WITH RS FILL
    # Mix dependencies while keeping RS full
    # ========================================================================
    
    addi x1, x0, 10
    addi x2, x0, 20
    addi x3, x0, 30
    
    # Dependent pair
    mul  x4, x1, x2         # x4 = 200
    mul  x5, x4, x3         # x5 = 6000 (depends on x4)
    
    # Independent ops to fill RS
    mul  x6, x1, x3         # Independent
    mul  x7, x2, x3         # Independent
    
    # Another dependent pair
    div  x8, x5, x2         # x8 = 300 (depends on x5)
    div  x9, x8, x1         # x9 = 30 (depends on x8)
    
    # More independent ops
    mul  x10, x1, x1        # Independent
    mul  x11, x2, x2        # Independent
    mul  x12, x3, x3        # Independent
    
    # Another dependency
    add  x13, x9, x10       # Depends on x9 and x10
    
    # Fill remaining RS slots
    mul  x14, x1, x2
    mul  x15, x2, x3
    mul  x16, x3, x1
    div  x17, x1, x2
    div  x18, x2, x3
    div  x19, x3, x1
    
    nop
    nop
    nop
    nop
    nop
    
    # ========================================================================
    # TEST 8: MAXIMUM RS STRESS - ALL UNITS FULL (8 entries each)
    # Issue maximum number of operations across all functional units
    # Goal: Fill every reservation station (MUL: 8, DIV: 8, ALU: 8)
    # Total: 24 RS slots across all units, then overflow
    # ========================================================================
    
    # Initialize 16 unique values
    addi x1, x0, 1
    addi x2, x0, 2
    addi x3, x0, 3
    addi x4, x0, 4
    addi x5, x0, 5
    addi x6, x0, 6
    addi x7, x0, 7
    addi x8, x0, 8
    addi x9, x0, 9
    addi x10, x0, 10
    addi x11, x0, 11
    addi x12, x0, 12
    addi x13, x0, 13
    addi x14, x0, 14
    addi x15, x0, 15
    addi x16, x0, 16
    
    # Fill MUL RS (8 slots)
    mul  x17, x1, x2        # MUL RS 1/8
    mul  x18, x3, x4        # MUL RS 2/8
    mul  x19, x5, x6        # MUL RS 3/8
    mul  x20, x7, x8        # MUL RS 4/8
    mul  x21, x9, x10       # MUL RS 5/8
    mul  x22, x11, x12      # MUL RS 6/8
    mul  x23, x13, x14      # MUL RS 7/8
    mul  x24, x15, x16      # MUL RS 8/8 (MUL RS FULL)
    
    # Fill DIV RS (8 slots)
    div  x25, x1, x2        # DIV RS 1/8
    div  x26, x3, x4        # DIV RS 2/8
    div  x27, x5, x6        # DIV RS 3/8
    div  x28, x7, x8        # DIV RS 4/8
    div  x29, x9, x1        # DIV RS 5/8
    div  x30, x10, x2       # DIV RS 6/8
    div  x31, x11, x3       # DIV RS 7/8
    div  x1, x12, x4        # DIV RS 8/8 (DIV RS FULL)
    
    # Fill ALU RS (8 slots)
    add  x2, x5, x6         # ALU RS 1/8
    sub  x3, x7, x8         # ALU RS 2/8
    xor  x4, x9, x10        # ALU RS 3/8
    or   x5, x11, x12       # ALU RS 4/8
    and  x6, x13, x14       # ALU RS 5/8
    sll  x7, x15, x1        # ALU RS 6/8
    srl  x8, x16, x1        # ALU RS 7/8
    sra  x9, x15, x1        # ALU RS 8/8 (ALU RS FULL)
    
    # Now ALL 24 RS slots are full (8 MUL + 8 DIV + 8 ALU)
    # Issue more operations - these must queue or stall
    mul  x10, x13, x15      # Should queue (MUL RS full)
    div  x11, x14, x5       # Should queue (DIV RS full)
    add  x12, x15, x16      # Should queue (ALU RS full)
    mul  x13, x14, x16      # Should queue (MUL RS full)
    div  x14, x15, x6       # Should queue (DIV RS full)
    sub  x15, x13, x14      # Should queue (ALU RS full)

    # ========================================================================
    # HALT
    # ========================================================================
halt:
    slti x0, x0, -256
