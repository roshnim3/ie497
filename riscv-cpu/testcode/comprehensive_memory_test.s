.section .text
.globl _start

_start:
    # Initialize base address
    auipc x1, 0                 # x1 = PC (0xAAAAA000)
    addi x1, x1, 224            # x1 points to data section (0xe0 offset)

    # Test 1: Independent loads (no dependencies)
    lw x2, 0(x1)                # Load word 0x11111111
    lw x3, 4(x1)                # Load word 0x22222222
    lw x4, 8(x1)                # Load word 0x33333333
    lw x5, 12(x1)               # Load word 0x44444444

    # Test 2: Dependent loads (address dependency)
    lw x6, 16(x1)               # Load x6 = offset value (0x00000008)
    add x7, x1, x6              # x7 = x1 + x6 (base + 8)
    lw x8, 0(x7)                # Load from x1+8 (should get 0x33333333)

    # Test 3: Load-to-ALU dependency
    lw x9, 20(x1)               # Load x9 = 0x00000003
    addi x10, x9, 5             # x10 = x9 + 5 = 8
    slli x11, x10, 2            # x11 = x10 << 2 = 32

    # Test 4: Store independent values
    sw x2, 64(x1)               # Store x2 to offset 64
    sw x3, 68(x1)               # Store x3 to offset 68
    sw x4, 72(x1)               # Store x4 to offset 72
    sw x5, 76(x1)               # Store x5 to offset 76

    # Test 5: Store computed values
    sw x8, 80(x1)               # Store x8 (dependent load result)
    sw x10, 84(x1)              # Store x10 (ALU result)
    sw x11, 88(x1)              # Store x11 (shift result)

    # Test 6: Load-after-store (verify forwarding if implemented)
    sw x2, 92(x1)               # Store x2
    lw x12, 92(x1)              # Load back (should get x2's value)

    # Test 7: Multiple stores then multiple loads
    sw x3, 96(x1)
    sw x4, 100(x1)
    sw x5, 104(x1)
    lw x13, 96(x1)              # Should get x3
    lw x14, 100(x1)             # Should get x4
    lw x15, 104(x1)             # Should get x5

    # Test 8: Store with address computation
    addi x16, x1, 108           # x16 = x1 + 108
    sw x2, 0(x16)               # Store x2 at x1+108
    lw x17, 108(x1)             # Verify by loading

    # Test 9: Half-word and byte operations
    lh x18, 0(x1)               # Load half from offset 0
    lh x19, 2(x1)               # Load half from offset 2
    lb x20, 0(x1)               # Load byte from offset 0
    lb x21, 1(x1)               # Load byte from offset 1

    # Test 10: Store half and byte
    sh x18, 112(x1)             # Store half
    sb x20, 114(x1)             # Store byte
    lw x22, 112(x1)             # Load word to verify

    # Test 11: Chain of dependent operations
    lw x23, 24(x1)              # Load base value
    addi x24, x23, 10           # Add 10
    sw x24, 116(x1)             # Store result
    lw x25, 116(x1)             # Load it back
    addi x26, x25, 20           # Add 20 more
    sw x26, 120(x1)             # Store final result

    # Test 12: Multiple loads from same address
    lw x27, 0(x1)
    lw x28, 0(x1)
    add x29, x27, x28           # Should be 2 * first value

    # Test 13: Stores to same location (last write wins)
    sw x2, 124(x1)              # Write x2
    sw x3, 124(x1)              # Overwrite with x3
    sw x4, 124(x1)              # Overwrite with x4
    lw x30, 124(x1)             # Should get x4

halt:
    slti x0, x0, -256           # Halt instruction
    nop
    nop

.align 4
data_section:
    .word 0x11111111            # Offset 0
    .word 0x22222222            # Offset 4
    .word 0x33333333            # Offset 8
    .word 0x44444444            # Offset 12
    .word 0x00000008            # Offset 16 (offset value)
    .word 0x00000003            # Offset 20 (small value)
    .word 0x55555555            # Offset 24
    .word 0x66666666            # Offset 28
    
    # Space for stores
    .word 0x00000000            # Offset 32
    .word 0x00000000            # Offset 36
    .word 0x00000000            # Offset 40
    .word 0x00000000            # Offset 44
    .word 0x00000000            # Offset 48
    .word 0x00000000            # Offset 52
    .word 0x00000000            # Offset 56
    .word 0x00000000            # Offset 60
    .word 0x00000000            # Offset 64
    .word 0x00000000            # Offset 68
    .word 0x00000000            # Offset 72
    .word 0x00000000            # Offset 76
    .word 0x00000000            # Offset 80
    .word 0x00000000            # Offset 84
    .word 0x00000000            # Offset 88
    .word 0x00000000            # Offset 92
    .word 0x00000000            # Offset 96
    .word 0x00000000            # Offset 100
    .word 0x00000000            # Offset 104
    .word 0x00000000            # Offset 108
    .word 0x00000000            # Offset 112
    .word 0x00000000            # Offset 116
    .word 0x00000000            # Offset 120
    .word 0x00000000            # Offset 124
