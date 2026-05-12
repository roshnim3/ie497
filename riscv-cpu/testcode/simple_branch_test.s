.section .text
.globl _start

_start:
    # Initialize registers
    addi x1, x0, 10      # x1 = 10
    addi x2, x0, 5       # x2 = 5
    addi x3, x0, 0       # x3 = 0 (counter)
    
    # First branch - TAKEN (mispredicted since we predict not_taken)
    beq x1, x1, taken1   # Branch on equal - x1 == x1 is always true
    addi x3, x3, 100     # Should NOT execute (branch is taken)
    
taken1:
    addi x3, x3, 1       # x3 = 1 (should execute)
    
    # Second branch - NOT TAKEN (correctly predicted)
    bne x1, x1, taken2   # Branch on not equal - x1 != x1 is always false
    addi x3, x3, 1       # x3 = 2 (should execute)
    
taken2:
    addi x3, x3, 10      # x3 = 12 (should execute)
    
    # Third branch - TAKEN (mispredicted)
    blt x2, x1, taken3   # Branch less than - 5 < 10 is true
    addi x3, x3, 100     # Should NOT execute
    
taken3:
    addi x3, x3, 1       # x3 = 13 (should execute)
    
    # Fourth branch - NOT TAKEN (correctly predicted)
    bge x1, x2, end      # Branch greater or equal - 10 >= 5 is true, TAKEN!
    addi x3, x3, 100     # Should NOT execute
    
end:
    addi x3, x3, 1       # x3 = 14 (final value)
    
    # JAL test - always taken but not a conditional branch
    jal x4, jal_target
    addi x3, x3, 100     # Should NOT execute
    
jal_target:
    addi x3, x3, 1       # x3 = 15
    
    # JALR test - use la (load address) pseudo-instruction
    la x5, jalr_target
    jalr x6, x5, 0
    addi x3, x3, 100     # Should NOT execute
    
jalr_target:
    addi x3, x3, 1       # x3 = 16 (final value)

_halt:
    slti x0, x0, -256    # Halt
