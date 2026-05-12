.section .text
.globl _start

_start:
    # Set up base pointer to data section
    auipc x1, 0                     # rob_idx=0: x1 = PC
    addi x1, x1, 512                # rob_idx=1: x1 = base address (well past code)

    # ========================================
    # Test 1: Simple RAW (Read After Write)
    # ========================================
    addi x2, x0, 100                # rob_idx=2
    sw x2, 0(x1)                    # rob_idx=3: Store 100
    lw x3, 0(x1)                    # rob_idx=4: Load 100 (depends on rob_idx=3)
    
    # ========================================
    # Test 2: WAW (Write After Write) - last write wins
    # ========================================
    addi x4, x0, 111                # rob_idx=5
    addi x5, x0, 222                # rob_idx=6
    addi x6, x0, 333                # rob_idx=7
    sw x4, 4(x1)                    # rob_idx=8: First write
    sw x5, 4(x1)                    # rob_idx=9: Second write
    sw x6, 4(x1)                    # rob_idx=10: Final write
    lw x7, 4(x1)                    # rob_idx=11: Should get 333
    
    # ========================================
    # Test 3: Byte operations with dependencies
    # ========================================
    addi x8, x0, 0xDD               # rob_idx=12
    sb x8, 8(x1)                    # rob_idx=13: Store byte
    lbu x9, 8(x1)                   # rob_idx=14: Load byte (depends on rob_idx=13)
    
    # ========================================
    # Test 4: Halfword operations
    # ========================================
    addi x10, x0, 0x1FF             # rob_idx=15
    sh x10, 10(x1)                  # rob_idx=16: Store halfword
    lhu x11, 10(x1)                 # rob_idx=17: Load halfword (depends on rob_idx=16)
    
    # ========================================
    # Test 5: Dependency chain
    # ========================================
    addi x12, x0, 1                 # rob_idx=18
    sw x12, 12(x1)                  # rob_idx=19
    lw x13, 12(x1)                  # rob_idx=20
    addi x13, x13, 1                # rob_idx=21: x13 = 2
    sw x13, 16(x1)                  # rob_idx=22
    lw x14, 16(x1)                  # rob_idx=23
    addi x14, x14, 1                # rob_idx=24: x14 = 3
    sw x14, 20(x1)                  # rob_idx=25
    
    # ========================================
    # Test 6: Multiple loads from same location
    # ========================================
    addi x15, x0, 777               # rob_idx=26
    sw x15, 24(x1)                  # rob_idx=27
    lw x16, 24(x1)                  # rob_idx=28
    lw x17, 24(x1)                  # rob_idx=29
    lw x18, 24(x1)                  # rob_idx=30
    
    # ========================================
    # Test 7: Signed loads
    # ========================================
    addi x19, x0, -128              # rob_idx=31: 0xFFFFFF80
    sb x19, 28(x1)                  # rob_idx=32
    lb x20, 28(x1)                  # rob_idx=33: Sign-extended load
    
    addi x21, x0, -256              # rob_idx=34: 0xFFFFFF00
    sh x21, 30(x1)                  # rob_idx=35
    lh x22, 30(x1)                  # rob_idx=36: Sign-extended load
    
    # ========================================
    # Test 8: Interleaved independent stores
    # ========================================
    addi x23, x0, 444               # rob_idx=37
    addi x24, x0, 555               # rob_idx=38
    sw x23, 32(x1)                  # rob_idx=39
    sw x24, 36(x1)                  # rob_idx=40 (independent)
    lw x25, 32(x1)                  # rob_idx=41
    lw x26, 36(x1)                  # rob_idx=42
    
    # ========================================
    # Test 9: Store-compute-store chain
    # ========================================
    addi x27, x0, 10                # rob_idx=43
    sw x27, 40(x1)                  # rob_idx=44
    lw x28, 40(x1)                  # rob_idx=45
    slli x29, x28, 2                # rob_idx=46: x29 = 40
    sw x29, 44(x1)                  # rob_idx=47
    lw x30, 44(x1)                  # rob_idx=48
    
    # ========================================
    # Test 10: Adjacent byte stores
    # ========================================
    addi x2, x0, 0x11               # rob_idx=49
    addi x3, x0, 0x22               # rob_idx=50
    addi x4, x0, 0x33               # rob_idx=51
    addi x5, x0, 0x44               # rob_idx=52
    sb x2, 48(x1)                   # rob_idx=53
    sb x3, 49(x1)                   # rob_idx=54
    sb x4, 50(x1)                   # rob_idx=55
    sb x5, 51(x1)                   # rob_idx=56
    lw x6, 48(x1)                   # rob_idx=57: Should get combined bytes
    
    # ========================================
    # Test 11: Final rapid stores and loads
    # ========================================
    addi x7, x0, 999                # rob_idx=58
    addi x8, x0, 888                # rob_idx=59
    sw x7, 52(x1)                   # rob_idx=60
    sw x8, 56(x1)                   # rob_idx=61
    lw x9, 52(x1)                   # rob_idx=62
    lw x10, 56(x1)                  # rob_idx=63
    add x11, x9, x10                # rob_idx=64
    sw x11, 60(x1)                  # rob_idx=65
    
    # Success
    addi x31, x0, 0                 # rob_idx=66
    
halt:
    slti x0, x0, -256

.section .rodata
.balign 256
