.align 4
.section .text
.globl _start
    # Simple frontend test
    # Tests instruction fetching in order
_start:

# Simple sequential instructions for testing fetch
addi x1, x0, 1      # x1 = 1
addi x2, x0, 2      # x2 = 2
addi x3, x0, 3      # x3 = 3
addi x4, x0, 4      # x4 = 4
addi x5, x0, 5      # x5 = 5
addi x6, x0, 6      # x6 = 6
addi x7, x0, 7      # x7 = 7
addi x8, x0, 8      # x8 = 8
addi x9, x0, 9      # x9 = 9
addi x10, x0, 10    # x10 = 10
add  x11, x1, x2    # x11 = x1 + x2
add  x12, x3, x4    # x12 = x3 + x4
add  x13, x5, x6    # x13 = x5 + x6
xor  x14, x7, x8    # x14 = x7 ^ x8
and  x15, x9, x10   # x15 = x9 & x10

halt:
    slti x0, x0, -256
