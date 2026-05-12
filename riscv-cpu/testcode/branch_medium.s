# Medium Branch Test
# Tests main branch types without too many instructions
# Expected final state: x31 = 0x0000000a (10 in decimal)

.section .text
.globl _start

_start:
    li x31, 0          # x31 = final result accumulator

# Test 1: BEQ taken
    li x10, 5
    li x11, 5
    beq x10, x11, t1_ok
    li x1, 1
t1_ok:
    addi x31, x31, 1   # x31 = 1

# Test 2: BNE taken  
    li x10, 5
    li x11, 6
    bne x10, x11, t2_ok
    li x1, 2
t2_ok:
    addi x31, x31, 1   # x31 = 2

# Test 3: BLT taken
    li x10, 3
    li x11, 8
    blt x10, x11, t3_ok
    li x1, 3
t3_ok:
    addi x31, x31, 1   # x31 = 3

# Test 4: BGE taken
    li x10, 9
    li x11, 9
    bge x10, x11, t4_ok
    li x1, 4
t4_ok:
    addi x31, x31, 1   # x31 = 4

# Test 5: BLTU taken
    li x10, 5
    li x11, 10
    bltu x10, x11, t5_ok
    li x1, 5
t5_ok:
    addi x31, x31, 1   # x31 = 5

# Test 6: BGEU taken
    li x10, 12
    li x11, 12
    bgeu x10, x11, t6_ok
    li x1, 6
t6_ok:
    addi x31, x31, 1   # x31 = 6

# Test 7: JAL
    jal x6, t7_ok
    li x1, 7
t7_ok:
    addi x31, x31, 1   # x31 = 7

# Test 8: Backward branch (loop)
    li x14, 0
    li x15, 2
loop:
    addi x14, x14, 1
    blt x14, x15, loop
    addi x31, x31, 1   # x31 = 8

# Test 9: Not taken branches
    li x20, 5
    li x21, 10
    beq x20, x21, error
    bge x20, x21, error
    addi x31, x31, 1   # x31 = 9

# Test 10: Chain
    li x22, 1
    beq x22, x22, chain1
    j error
chain1:
    bne x22, x0, chain2
    j error
chain2:
    addi x31, x31, 1   # x31 = 10

# Success
success:
    slti x0, x0, -256

error:
    li x1, 99
    slti x0, x0, -256

.section .rodata
.balign 4
