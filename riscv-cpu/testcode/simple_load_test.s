.section .text
.globl _start

_start:
    # Initialize base addresses using auipc
    # PC starts at 0xAAAAA000, so auipc will add offset to current PC
    # Instructions: auipc(4) + addi(4) + 5*lw(20) + 5*sw(20) + slti(4) + 2*nop(8) = 60 bytes
    auipc x1, 0             # x1 = PC + 0 (points to this instruction)
    addi x1, x1, 60         # Adjust to point to data section (60 bytes to skip code)
    
    # 5 independent loads - each loads from different address to different register
    lw x2, 0(x1)            # Load word from x1+0 to x2
    lw x3, 4(x1)            # Load word from x1+4 to x3
    lw x4, 8(x1)            # Load word from x1+8 to x4
    lw x5, 12(x1)           # Load word from x1+12 to x5
    lw x6, 16(x1)           # Load word from x1+16 to x6
    
    # Store results back to verify
    sw x2, 32(x1)           # Store x2 to x1+32
    sw x3, 36(x1)           # Store x3 to x1+36
    sw x4, 40(x1)           # Store x4 to x1+40
    sw x5, 44(x1)           # Store x5 to x1+44
    sw x6, 48(x1)           # Store x6 to x1+48

halt:
    slti x0, x0, -256       # Halt instruction
    nop
    nop

.align 4
data_section:
    .word 0x11111111        # Data at offset 0
    .word 0x22222222        # Data at offset 4
    .word 0x33333333        # Data at offset 8
    .word 0x44444444        # Data at offset 12
    .word 0x55555555        # Data at offset 16
    .word 0x00000000        # Space for stores (offset 20)
    .word 0x00000000        # Space for stores (offset 24)
    .word 0x00000000        # Space for stores (offset 28)
    .word 0x00000000        # Space for stores (offset 32)
    .word 0x00000000        # Space for stores (offset 36)
    .word 0x00000000        # Space for stores (offset 40)
    .word 0x00000000        # Space for stores (offset 44)
    .word 0x00000000        # Space for stores (offset 48)
