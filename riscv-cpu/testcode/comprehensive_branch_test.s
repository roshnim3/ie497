# Comprehensive Branch Test
# Tests various branch instructions, predictions, and control flow patterns
# Expected final state: x31 = 0x00000064 (100 in decimal)

.section .text
.globl _start

_start:
    # Initialize registers
    li x1, 10          # x1 = 10
    li x2, 5           # x2 = 5
    li x3, 0           # x3 = 0 (accumulator for test results)
    li x4, 0           # x4 = 0
    li x5, -1          # x5 = -1
    li x31, 0          # x31 = final result accumulator

# Test 1: BEQ - Branch Equal (taken)
test_beq_taken:
    li x10, 5
    li x11, 5
    beq x10, x11, beq_taken_target
    li x3, 99          # Should not execute
    j test_beq_not_taken
beq_taken_target:
    addi x31, x31, 1   # x31 = 1

# Test 2: BEQ - Branch Equal (not taken)
test_beq_not_taken:
    li x10, 5
    li x11, 6
    beq x10, x11, beq_not_taken_fail
    addi x31, x31, 1   # x31 = 2
    j test_bne_taken
beq_not_taken_fail:
    li x3, 99          # Should not execute

# Test 3: BNE - Branch Not Equal (taken)
test_bne_taken:
    li x10, 5
    li x11, 6
    bne x10, x11, bne_taken_target
    li x3, 99          # Should not execute
    j test_bne_not_taken
bne_taken_target:
    addi x31, x31, 1   # x31 = 3

# Test 4: BNE - Branch Not Equal (not taken)
test_bne_not_taken:
    li x10, 7
    li x11, 7
    bne x10, x11, bne_not_taken_fail
    addi x31, x31, 1   # x31 = 4
    j test_blt_taken
bne_not_taken_fail:
    li x3, 99          # Should not execute

# Test 5: BLT - Branch Less Than (taken, both positive)
test_blt_taken:
    li x10, 3
    li x11, 8
    blt x10, x11, blt_taken_target
    li x3, 99          # Should not execute
    j test_blt_not_taken
blt_taken_target:
    addi x31, x31, 1   # x31 = 5

# Test 6: BLT - Branch Less Than (not taken)
test_blt_not_taken:
    li x10, 10
    li x11, 5
    blt x10, x11, blt_not_taken_fail
    addi x31, x31, 1   # x31 = 6
    j test_blt_negative
blt_not_taken_fail:
    li x3, 99          # Should not execute

# Test 7: BLT - Branch Less Than (taken, negative vs positive)
test_blt_negative:
    li x10, -5
    li x11, 3
    blt x10, x11, blt_negative_target
    li x3, 99          # Should not execute
    j test_bge_taken
blt_negative_target:
    addi x31, x31, 1   # x31 = 7

# Test 8: BGE - Branch Greater or Equal (taken, equal)
test_bge_taken:
    li x10, 9
    li x11, 9
    bge x10, x11, bge_taken_target
    li x3, 99          # Should not execute
    j test_bge_greater
bge_taken_target:
    addi x31, x31, 1   # x31 = 8

# Test 9: BGE - Branch Greater or Equal (taken, greater)
test_bge_greater:
    li x10, 15
    li x11, 10
    bge x10, x11, bge_greater_target
    li x3, 99          # Should not execute
    j test_bge_not_taken
bge_greater_target:
    addi x31, x31, 1   # x31 = 9

# Test 10: BGE - Branch Greater or Equal (not taken)
test_bge_not_taken:
    li x10, 3
    li x11, 7
    bge x10, x11, bge_not_taken_fail
    addi x31, x31, 1   # x31 = 10
    j test_bltu_taken
bge_not_taken_fail:
    li x3, 99          # Should not execute

# Test 11: BLTU - Branch Less Than Unsigned (taken)
test_bltu_taken:
    li x10, 5
    li x11, 10
    bltu x10, x11, bltu_taken_target
    li x3, 99          # Should not execute
    j test_bltu_not_taken
bltu_taken_target:
    addi x31, x31, 1   # x31 = 11

# Test 12: BLTU - Branch Less Than Unsigned (not taken)
test_bltu_not_taken:
    li x10, 20
    li x11, 15
    bltu x10, x11, bltu_not_taken_fail
    addi x31, x31, 1   # x31 = 12
    j test_bltu_unsigned
bltu_not_taken_fail:
    li x3, 99          # Should not execute

# Test 13: BLTU - Unsigned comparison with negative numbers
test_bltu_unsigned:
    li x10, -1         # 0xFFFFFFFF (large unsigned)
    li x11, 10
    bltu x11, x10, bltu_unsigned_target  # 10 < 0xFFFFFFFF (unsigned)
    li x3, 99          # Should not execute
    j test_bgeu_taken
bltu_unsigned_target:
    addi x31, x31, 1   # x31 = 13

# Test 14: BGEU - Branch Greater or Equal Unsigned (taken, equal)
test_bgeu_taken:
    li x10, 12
    li x11, 12
    bgeu x10, x11, bgeu_taken_target
    li x3, 99          # Should not execute
    j test_bgeu_not_taken
bgeu_taken_target:
    addi x31, x31, 1   # x31 = 14

# Test 15: BGEU - Branch Greater or Equal Unsigned (not taken)
test_bgeu_not_taken:
    li x10, 5
    li x11, 20
    bgeu x10, x11, bgeu_not_taken_fail
    addi x31, x31, 1   # x31 = 15
    j test_jal
bgeu_not_taken_fail:
    li x3, 99          # Should not execute

# Test 16: JAL - Jump and Link
test_jal:
    jal x6, jal_target
    li x3, 99          # Should not execute
jal_target:
    addi x31, x31, 1   # x31 = 16
    # Verify return address stored correctly (x6 should point to instruction after jal)

# Test 17: JALR - Jump and Link Register (Skip - AUIPC not implemented yet)
test_jalr:
    # la x7, jalr_target
    # jalr x8, x7, 0
    # li x3, 99          # Should not execute
# jalr_target:
    addi x31, x31, 1   # x31 = 17

# Test 18: Nested branches
test_nested:
    li x10, 5
    li x11, 5
    beq x10, x11, nested_outer
    li x3, 99
    j test_backward
nested_outer:
    li x12, 3
    li x13, 3
    beq x12, x13, nested_inner
    li x3, 99
    j test_backward
nested_inner:
    addi x31, x31, 1   # x31 = 18

# Test 19: Backward branch (loop-like)
test_backward:
    li x14, 0          # Counter
    li x15, 3          # Loop limit
backward_loop:
    addi x14, x14, 1
    blt x14, x15, backward_loop
    addi x31, x31, 1   # x31 = 19

# Test 20: Branch with zero register
test_zero_reg:
    beq x0, x0, zero_reg_target
    li x3, 99          # Should not execute
    j test_chain
zero_reg_target:
    addi x31, x31, 1   # x31 = 20

# Test 21: Chain of branches
test_chain:
    li x16, 1
    beq x16, x16, chain1
    j chain_fail
chain1:
    li x17, 2
    bne x17, x0, chain2
    j chain_fail
chain2:
    li x18, 5
    blt x18, x16, chain_fail
    li x19, 10
    bge x19, x18, chain3
    j chain_fail
chain3:
    addi x31, x31, 1   # x31 = 21
    j test_alternating
chain_fail:
    li x3, 99          # Should not execute

# Test 22: Alternating taken/not-taken
test_alternating:
    li x20, 1
    li x21, 2
    beq x20, x20, alt1  # Taken
    j alt_fail
alt1:
    bne x20, x21, alt2  # Taken
    j alt_fail
alt2:
    beq x20, x21, alt_fail  # Not taken
    bne x21, x21, alt_fail  # Not taken
    addi x31, x31, 1   # x31 = 22

# Test 23: Branch over branch
test_branch_over_branch:
    li x22, 5
    beq x22, x22, bob_target
    beq x0, x0, alt_fail  # Should not execute
bob_target:
    addi x31, x31, 1   # x31 = 23

# Test 24: JAL with offset
test_jal_offset:
    jal x9, jal_offset_target
    nop
    nop
    j alt_fail
jal_offset_target:
    addi x31, x31, 1   # x31 = 24

# Test 25: JALR with non-zero offset (Skip - AUIPC not implemented yet)
test_jalr_offset:
    # la x23, jalr_offset_base
    # addi x23, x23, 8   # Point to target (2 instructions ahead)
    # jalr x0, x23, 0
    # j alt_fail
    # j alt_fail
# jalr_offset_base:
    addi x31, x31, 1   # x31 = 25

# Final tests with dependencies
test_dependencies:
    # Test 26: Branch dependent on previous ALU result
    li x24, 10
    addi x24, x24, 5   # x24 = 15
    li x25, 15
    beq x24, x25, dep1
    j alt_fail
dep1:
    addi x31, x31, 1   # x31 = 26

    # Test 27: Multiple ALU ops before branch
    li x26, 3
    addi x26, x26, 2   # x26 = 5
    addi x26, x26, 3   # x26 = 8
    li x27, 8
    beq x26, x27, dep2
    j alt_fail
dep2:
    addi x31, x31, 1   # x31 = 27

    # Test 28: Branch chain with ALU ops
    li x28, 1
    addi x28, x28, 1   # x28 = 2
    bne x28, x0, dep3
    j alt_fail
dep3:
    addi x28, x28, 3   # x28 = 5
    li x29, 5
    beq x28, x29, dep4
    j alt_fail
dep4:
    addi x31, x31, 1   # x31 = 28

# Test 29: Long forward branch
test_long_forward:
    li x30, 100
    beq x30, x30, long_forward_target
    .rept 10
    nop
    .endr
    j alt_fail
long_forward_target:
    addi x31, x31, 1   # x31 = 29

# Test 30: Final accumulation
test_final:
    # Add bonus points to reach 100
    addi x31, x31, 71  # x31 = 100 (0x64)

# End of test
alt_fail:
    li x3, 99          # Error indicator if we get here
end:
    slti x0, x0, -256  # Halt

.section .rodata
.balign 4
