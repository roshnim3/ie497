.section .text
.globl _start

_start:
    # Initialize some registers with immediate values
    addi x1, x0, 10         # x1 = 10
    addi x2, x0, 20         # x2 = 20
    addi x3, x0, -5         # x3 = -5
    addi x4, x0, 15         # x4 = 15
    addi x5, x0, 100        # x5 = 100
    
    # Test ADDI - Add immediate
    addi x6, x1, 5          # x6 = 10 + 5 = 15
    addi x7, x2, -10        # x7 = 20 - 10 = 10
    addi x8, x3, 25         # x8 = -5 + 25 = 20
    
    # Test SLTI - Set less than immediate (signed)
    slti x9, x1, 15         # x9 = (10 < 15) = 1
    slti x10, x2, 10        # x10 = (20 < 10) = 0
    slti x11, x3, 0         # x11 = (-5 < 0) = 1
    
    # Test SLTIU - Set less than immediate (unsigned)
    sltiu x12, x1, 15       # x12 = (10 < 15) = 1
    sltiu x13, x5, 50       # x13 = (100 < 50) = 0
    
    # Test XORI - XOR immediate
    xori x14, x1, 7         # x14 = 10 ^ 7 = 13
    xori x15, x2, 31        # x15 = 20 ^ 31 = 11
    
    # Test ORI - OR immediate
    ori x16, x1, 5          # x16 = 10 | 5 = 15
    ori x17, x2, 8          # x17 = 20 | 8 = 28
    
    # Test ANDI - AND immediate
    andi x18, x1, 14        # x18 = 10 & 14 = 10
    andi x19, x2, 16        # x19 = 20 & 16 = 16
    
    # Test SLLI - Shift left logical immediate
    slli x20, x1, 2         # x20 = 10 << 2 = 40
    slli x21, x2, 1         # x21 = 20 << 1 = 40
    
    # Test SRLI - Shift right logical immediate
    srli x22, x5, 2         # x22 = 100 >> 2 = 25
    srli x23, x2, 1         # x23 = 20 >> 1 = 10
    
    # Test SRAI - Shift right arithmetic immediate
    srai x24, x3, 1         # x24 = -5 >> 1 = -3 (arithmetic)
    srai x25, x1, 1         # x25 = 10 >> 1 = 5
    
    # Test ADD - Add registers
    add x26, x1, x2         # x26 = 10 + 20 = 30
    add x27, x3, x4         # x27 = -5 + 15 = 10
    add x28, x6, x7         # x28 = 15 + 10 = 25
    
    # Test SUB - Subtract registers
    sub x29, x2, x1         # x29 = 20 - 10 = 10
    sub x30, x4, x3         # x30 = 15 - (-5) = 20
    sub x31, x5, x1         # x31 = 100 - 10 = 90
    
    # Test SLL - Shift left logical
    sll x6, x1, x1          # x6 = 10 << (10 & 0x1F) = 10240
    addi x2, x0, 3          # x2 = 3 (shift amount)
    sll x7, x4, x2          # x7 = 15 << 3 = 120
    
    # Test SLT - Set less than (signed)
    slt x8, x1, x2          # x8 = (10 < 3) = 0
    slt x9, x3, x1          # x9 = (-5 < 10) = 1
    
    # Test SLTU - Set less than (unsigned)
    sltu x10, x1, x2        # x10 = (10 < 3) = 0
    sltu x11, x2, x4        # x11 = (3 < 15) = 1
    
    # Test XOR - XOR registers
    xor x12, x1, x2         # x12 = 10 ^ 3 = 9
    xor x13, x4, x5         # x13 = 15 ^ 100 = 111
    
    # Test SRL - Shift right logical
    srl x14, x5, x2         # x14 = 100 >> 3 = 12
    addi x2, x0, 2          # x2 = 2
    srl x15, x4, x2         # x15 = 15 >> 2 = 3
    
    # Test SRA - Shift right arithmetic
    sra x16, x3, x2         # x16 = -5 >> 2 = -2 (arithmetic)
    sra x17, x1, x2         # x17 = 10 >> 2 = 2
    
    # Test OR - OR registers
    or x18, x1, x2          # x18 = 10 | 2 = 10
    or x19, x4, x5          # x19 = 15 | 100 = 111
    
    # Test AND - AND registers
    and x20, x1, x4         # x20 = 10 & 15 = 10
    and x21, x2, x5         # x21 = 2 & 100 = 0
    
    # More complex ALU instruction chains
    addi x1, x0, 42         # x1 = 42
    addi x2, x0, 7          # x2 = 7
    add x3, x1, x2          # x3 = 49
    sub x4, x3, x2          # x4 = 42
    xori x5, x4, 255        # x5 = 42 ^ 255 = 213
    andi x6, x5, 127        # x6 = 213 & 127 = 85
    ori x7, x6, 32          # x7 = 85 | 32 = 117
    slli x8, x7, 1          # x8 = 117 << 1 = 234
    srli x9, x8, 1          # x9 = 234 >> 1 = 117
    
    # Test with zero register
    add x10, x0, x0         # x10 = 0
    addi x11, x0, 0         # x11 = 0
    xor x12, x1, x0         # x12 = 42 ^ 0 = 42
    or x13, x0, x2          # x13 = 0 | 7 = 7
    and x14, x1, x0         # x14 = 42 & 0 = 0
    
    # LUI and AUIPC (upper immediate operations)
    lui x15, 0x12345        # x15 = 0x12345000
    auipc x16, 0x1000       # x16 = PC + 0x1000000
    lui x17, 0xFFFFF        # x17 = 0xFFFFF000
    auipc x18, 0           # x18 = PC
    
    # More immediate operations
    addi x19, x15, 0x123    # Add to upper immediate result
    xori x20, x17, -1       # XOR with all 1s
    ori x21, x15, 0x456     # OR with upper immediate result
    andi x22, x17, 0x7FF    # AND with upper immediate result
    
    # Final chain of operations
    addi x23, x0, 1         # x23 = 1
    slli x23, x23, 5        # x23 = 32
    addi x24, x23, -1       # x24 = 31
    and x25, x23, x24       # x25 = 32 & 31 = 0
    or x26, x23, x24        # x26 = 32 | 31 = 63
    xor x27, x23, x24       # x27 = 32 ^ 31 = 63
    
    addi x28, x0, 0         
    addi x28, x28, 1        
    addi x29, x0, 1000      
    slt x30, x28, x29       
    addi x28, x28, 1        
    addi x28, x28, 1        
    addi x28, x28, 1        
    
    addi x31, x0, -1        # Signal completion with -1

    slti x0, x0, -256       # Stop instruction for simulator
