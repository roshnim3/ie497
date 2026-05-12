# Comprehensive Branch Test (Short Version)
# Tests all branch types with various scenarios
# Expected final state: x31 = 0x00000014 (20 in decimal)

.section .text
.globl _start

_start:
    # Initialize registers
    li x31, 0          # x31 = final result accumulator

# Test 1: BEQ taken
test_beq_taken:
    li x10, 5
    li x11, 5
    beq x10, x11, beq_taken_ok
    li x1, 1           # Error
beq_taken_ok:
    addi x31, x31, 1   # x31 = 1

# Test 2: BEQ not taken
test_beq_not_taken:
    li x10, 5
    li x11, 6
    beq x10, x11, error
    addi x31, x31, 1   # x31 = 2

# Test 3: BNE taken
test_bne_taken:
    li x10, 5
    li x11, 6
    bne x10, x11, bne_taken_ok
    li x1, 3           # Error
bne_taken_ok:
    addi x31, x31, 1   # x31 = 3

# Test 4: BNE not taken
test_bne_not_taken:
    li x10, 7
    li x11, 7
    bne x10, x11, error
    addi x31, x31, 1   # x31 = 4

# Test 5: BLT taken (positive numbers)
test_blt_taken:
    li x10, 3
    li x11, 8
    blt x10, x11, blt_taken_ok
    li x1, 5           # Error
blt_taken_ok:
    addi x31, x31, 1   # x31 = 5

# Test 6: BLT not taken
test_blt_not_taken:
    li x10, 10
    li x11, 5
    blt x10, x11, error
    addi x31, x31, 1   # x31 = 6

# Test 7: BLT with negative (taken)
test_blt_negative:
    li x10, -5
    li x11, 3
    blt x10, x11, blt_neg_ok
    li x1, 7           # Error
blt_neg_ok:
    addi x31, x31, 1   # x31 = 7

# Test 8: BGE taken (equal)
test_bge_equal:
    li x10, 9
    li x11, 9
    bge x10, x11, bge_equal_ok
    li x1, 8           # Error
bge_equal_ok:
    addi x31, x31, 1   # x31 = 8

# Test 9: BGE taken (greater)
test_bge_greater:
    li x10, 15
    li x11, 10
    bge x10, x11, bge_greater_ok
    li x1, 9           # Error
bge_greater_ok:
    addi x31, x31, 1   # x31 = 9

# Test 10: BGE not taken
test_bge_not_taken:
    li x10, 3
    li x11, 7
    bge x10, x11, error
    addi x31, x31, 1   # x31 = 10

# Test 11: BLTU taken
test_bltu_taken:
    li x10, 5
    li x11, 10
    bltu x10, x11, bltu_taken_ok
    li x1, 11          # Error
bltu_taken_ok:
    addi x31, x31, 1   # x31 = 11

# Test 12: BLTU not taken
test_bltu_not_taken:
    li x10, 20
    li x11, 15
    bltu x10, x11, error
    addi x31, x31, 1   # x31 = 12

# Test 13: BGEU taken (equal)
test_bgeu_equal:
    li x10, 12
    li x11, 12
    bgeu x10, x11, bgeu_equal_ok
    li x1, 13          # Error
bgeu_equal_ok:
    addi x31, x31, 1   # x31 = 13

# Test 14: BGEU not taken
test_bgeu_not_taken:
    li x10, 5
    li x11, 20
    bgeu x10, x11, error
    addi x31, x31, 1   # x31 = 14

# Test 15: JAL forward
test_jal:
    jal x6, jal_target
    li x1, 15          # Error - should not execute
jal_target:
    addi x31, x31, 1   # x31 = 15

# Test 16: Backward branch (simple loop)
test_backward:
    li x14, 0
    li x15, 3
backward_loop:
    addi x14, x14, 1
    blt x14, x15, backward_loop
    addi x31, x31, 1   # x31 = 16

# Test 17: Branch with x0
test_zero_reg:
    beq x0, x0, zero_ok
    li x1, 17          # Error
zero_ok:
    addi x31, x31, 1   # x31 = 17

# Test 18: Chain of branches
test_chain:
    li x16, 1
    beq x16, x16, chain1
    j error
chain1:
    li x17, 2
    bne x17, x0, chain2
    j error
chain2:
    addi x31, x31, 1   # x31 = 18

# Test 19: ALU dependency before branch
test_dependency:
    li x20, 10
    addi x20, x20, 5   # x20 = 15
    li x21, 15
    beq x20, x21, dep_ok
    j error
dep_ok:
    addi x31, x31, 1   # x31 = 19

# Test 20: Multiple sequential branches
test_sequential:
    li x22, 5
    li x23, 5
    beq x22, x23, seq1
    j error
seq1:
    bne x22, x0, seq2
    j error
seq2:
    blt x0, x22, seq3
    j error
seq3:
    bge x22, x0, seq4
    j error
seq4:
    addi x31, x31, 1   # x31 = 20

# Success - x31 should be 20
success:
    slti x0, x0, -256  # Halt

error:
    li x1, 99          # Error indicator
    slti x0, x0, -256  # Halt

.section .rodata
.balign 4
