.section .text
.globl _start

_start:
    # Load some test values
    li x1, 10
    li x2, 5
    li x3, 20
    li x4, 4
    
    # Multiplication tests
    mul x5, x1, x2      # x5 = 10 * 5 = 50
    mul x6, x3, x4      # x6 = 20 * 4 = 80
    mul x7, x5, x6      # x7 = 50 * 80 = 4000 (dependent on previous muls)
    
    # Division tests
    div x8, x3, x2      # x8 = 20 / 5 = 4
    div x9, x1, x4      # x9 = 10 / 4 = 2
    div x10, x7, x8     # x10 = 4000 / 4 = 1000 (dependent on mul and div)
    
    # Done - infinite loop
    slti x0, x0, -256
