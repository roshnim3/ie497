# Branch Predictor Test
# Tests GHR and PHT updates with various branch patterns

.section .text
.globl _start

_start:
    # Initialize registers
    addi x1, x0, 0
    addi x2, x0, 10
    addi x3, x0, 1
    
    # ========================================================================
    # TEST 1: Always Taken Branch (should train to Strongly Taken = 11)
    # ========================================================================
test1_loop:
    addi x1, x1, 1              # Increment counter
    blt  x1, x2, test1_loop     # Branch taken 10 times
    # After this, PHT entry should be 11 (strongly taken)
    
    # Reset counter
    addi x1, x0, 0
    
    # ========================================================================
    # TEST 2: Always Not Taken Branch (should train to Strongly Not Taken = 00)
    # ========================================================================
test2_skip:
    addi x1, x1, 1              # x1 = 1
    bge  x1, x2, test2_target   # Never taken (1 >= 10 is false)
    addi x4, x0, 1              # Continue here
    bge  x1, x2, test2_target   # Not taken again
    addi x4, x0, 2
    bge  x1, x2, test2_target   # Not taken again
    addi x4, x0, 3
    bge  x1, x2, test2_target   # Not taken again
    addi x4, x0, 4
    bge  x1, x2, test2_target   # Not taken again
    addi x4, x0, 5
    bge  x1, x2, test2_target   # Not taken again
    addi x4, x0, 6
    j test2_end
test2_target:
    addi x5, x0, 99             # Should not reach here
test2_end:
    # After this, PHT entry should be 00 (strongly not taken)
    
    # ========================================================================
    # TEST 3: Alternating Pattern (Taken, Not Taken, Taken, Not Taken, ...)
    # ========================================================================
    addi x1, x0, 0              # x1 = 0
    addi x6, x0, 0              # Counter for alternating
    
test3_loop:
    addi x6, x6, 1
    andi x7, x6, 1              # x7 = x6 % 2
    beq  x7, x0, test3_even     # Branch if even (taken half the time)
    addi x8, x0, 1              # Odd case
    j test3_cont
test3_even:
    addi x8, x0, 2              # Even case
test3_cont:
    addi x9, x0, 8
    blt  x6, x9, test3_loop     # Loop 8 times
    # PHT entry should oscillate or stay in middle (01 or 10)
    
    # ========================================================================
    # TEST 4: Strongly Taken, then switch to Not Taken
    # ========================================================================
    addi x10, x0, 0
    
    # First train as taken (4 times)
test4_train:
    addi x10, x10, 1
    addi x11, x0, 5
    blt  x10, x11, test4_train  # Taken 4 times
    
    # Now make it not taken several times (should decrement counter)
    addi x10, x0, 10
    blt  x10, x11, test4_skip1  # Not taken (10 >= 5)
    addi x12, x0, 1
test4_skip1:
    blt  x10, x11, test4_skip2  # Not taken
    addi x12, x0, 2
test4_skip2:
    blt  x10, x11, test4_skip3  # Not taken
    addi x12, x0, 3
test4_skip3:
    blt  x10, x11, test4_skip4  # Not taken
    addi x12, x0, 4
test4_skip4:
    # Counter should decrease from 11 -> 10 -> 01 -> 00
    
    # ========================================================================
    # TEST 5: Different branch PCs to exercise different PHT entries
    # ========================================================================
    addi x13, x0, 5
    addi x14, x0, 3
    
    blt  x14, x13, test5_a      # Different PC, taken
    addi x15, x0, 1
test5_a:
    blt  x14, x13, test5_b      # Different PC, taken
    addi x15, x0, 2
test5_b:
    blt  x14, x13, test5_c      # Different PC, taken
    addi x15, x0, 3
test5_c:
    blt  x14, x13, test5_d      # Different PC, taken
    addi x15, x0, 4
test5_d:
    bge  x14, x13, test5_e      # Different PC, not taken
    addi x15, x0, 5
test5_e:
    bge  x14, x13, test5_end    # Different PC, not taken
    addi x15, x0, 6
test5_end:
    # Each branch should hash to different PHT entries due to different PCs
    
    # ========================================================================
    # TEST 6: GHR Test - Same branch PC, different history
    # ========================================================================
    addi x16, x0, 1
    addi x17, x0, 2
    
    # First path: taken -> taken -> branch X
    blt  x16, x17, ghr_path1    # Taken (GHR = ...1)
ghr_path1:
    blt  x16, x17, ghr_test1    # Taken (GHR = ...11)
ghr_test1:
    blt  x16, x17, ghr_cont1    # Target branch (GHR has ...11)
ghr_cont1:
    
    # Second path: not taken -> not taken -> branch X
    addi x16, x0, 10            # Make branches not taken
    bge  x16, x17, ghr_path2    # Not taken (GHR = ...0)
    j ghr_path2
ghr_path2:
    bge  x16, x17, ghr_test2    # Not taken (GHR = ...00)
    j ghr_test2
ghr_test2:
    blt  x16, x17, ghr_cont2    # Target branch (GHR has ...00)
    j ghr_cont2
ghr_cont2:
    # Same branch PC, but different GHR -> different PHT index
    
    # ========================================================================
    # TEST 7: Saturating counter test - try to overflow
    # ========================================================================
    addi x18, x0, 0
    addi x19, x0, 20
    
test7_loop:
    addi x18, x18, 1
    blt  x18, x19, test7_loop   # Taken 20 times
    # Counter should saturate at 11 (not overflow to 00)
    
    # ========================================================================
    # Halt
    # ========================================================================
    slti x0, x0, -256           # Halt instruction

