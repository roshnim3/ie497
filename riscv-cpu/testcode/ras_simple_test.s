.section .text
.globl _start

_start:
    # Simple nested function calls to test RAS (leaf functions, no stack needed)
    jal ra, func_a      # Call func_a (should push return address to RAS)
    
    # After return from func_a
    li a0, 100
    
    # Call another function
    jal ra, func_b      # Call func_b (should push return address to RAS)
    
    # Done 
    j _halt


func_a:
    # Leaf function - just do some work and return
    li a1, 1
    addi a1, a1, 2
    jalr x0, ra, 0      # Return (should pop from RAS, rd=x0 so it's detected as return)

func_b:
    # Another leaf function
    li a2, 2
    addi a2, a2, 3
    jalr x0, ra, 0      # Return (should pop from RAS, rd=x0 so it's detected as return)


_halt:
    slti x0, x0, -256    # Halt