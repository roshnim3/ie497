.align 4
.section .text
.globl _start
    # Comprehensive Long Frontend Test
    # Tests sustained instruction fetching with various instruction types
_start:

#==============================================================================
# Section 1: Basic Initialization (20 instructions)
#==============================================================================
li x1, 1
li x2, 2
li x3, 3
li x4, 4
li x5, 5
li x6, 6
li x7, 7
li x8, 8
li x9, 9
li x10, 10
li x11, 11
li x12, 12
li x13, 13
li x14, 14
li x15, 15
li x16, 16
li x17, 17
li x18, 18
li x19, 19
li x20, 20

#==============================================================================
# Section 2: Arithmetic Operations (40 instructions)
#==============================================================================
add x21, x1, x2
add x22, x3, x4
add x23, x5, x6
add x24, x7, x8
add x25, x9, x10
add x26, x11, x12
add x27, x13, x14
add x28, x15, x16

sub x21, x20, x1
sub x22, x19, x2
sub x23, x18, x3
sub x24, x17, x4
sub x25, x16, x5
sub x26, x15, x6
sub x27, x14, x7
sub x28, x13, x8

slt x21, x1, x10
slt x22, x2, x11
slt x23, x3, x12
slt x24, x4, x13
sltu x25, x5, x14
sltu x26, x6, x15
sltu x27, x7, x16
sltu x28, x8, x17

and x21, x1, x2
and x22, x3, x4
and x23, x5, x6
and x24, x7, x8
or x25, x9, x10
or x26, x11, x12
or x27, x13, x14
or x28, x15, x16

xor x21, x1, x20
xor x22, x2, x19
xor x23, x3, x18
xor x24, x4, x17

#==============================================================================
# Section 3: Shift Operations (30 instructions)
#==============================================================================
sll x21, x1, x2
sll x22, x3, x4
sll x23, x5, x6
sll x24, x7, x8
sll x25, x9, x10
sll x26, x11, x12
sll x27, x13, x14
sll x28, x15, x16

srl x21, x10, x1
srl x22, x11, x2
srl x23, x12, x3
srl x24, x13, x4
srl x25, x14, x5
srl x26, x15, x6
srl x27, x16, x7
srl x28, x17, x8

sra x21, x20, x1
sra x22, x19, x2
sra x23, x18, x3
sra x24, x17, x4
sra x25, x16, x5
sra x26, x15, x6
sra x27, x14, x7
sra x28, x13, x8

slli x21, x1, 1
slli x22, x2, 2
slli x23, x3, 3
slli x24, x4, 4
srli x25, x5, 1
srli x26, x6, 2

#==============================================================================
# Section 4: Immediate Operations (50 instructions)
#==============================================================================
addi x21, x1, 100
addi x22, x2, 200
addi x23, x3, 300
addi x24, x4, 400
addi x25, x5, 500
addi x26, x6, -100
addi x27, x7, -200
addi x28, x8, -300

slti x21, x1, 50
slti x22, x2, 100
slti x23, x3, 150
slti x24, x4, 200
sltiu x25, x5, 250
sltiu x26, x6, 300
sltiu x27, x7, 350
sltiu x28, x8, 400

xori x21, x1, 0xFF
xori x22, x2, 0xAA
xori x23, x3, 0x55
xori x24, x4, 0xF0
xori x25, x5, 0x0F
xori x26, x6, 0xCC
xori x27, x7, 0x33
xori x28, x8, 0x88

ori x21, x1, 0x01
ori x22, x2, 0x02
ori x23, x3, 0x04
ori x24, x4, 0x08
ori x25, x5, 0x10
ori x26, x6, 0x20
ori x27, x7, 0x40
ori x28, x8, 0x80

andi x21, x1, 0xFF
andi x22, x2, 0xFE
andi x23, x3, 0xFC
andi x24, x4, 0xF8
andi x25, x5, 0xF0
andi x26, x6, 0xE0
andi x27, x7, 0xC0
andi x28, x8, 0x80

srai x21, x20, 1
srai x22, x19, 2
srai x23, x18, 3
srai x24, x17, 4
srai x25, x16, 5
srai x26, x15, 6

#==============================================================================
# Section 5: Upper Immediate Operations (20 instructions)
#==============================================================================
lui x21, 0x12345
lui x22, 0xABCDE
lui x23, 0x11111
lui x24, 0x22222
lui x25, 0x33333
lui x26, 0x44444
lui x27, 0x55555
lui x28, 0x66666

auipc x21, 0x1000
auipc x22, 0x2000
auipc x23, 0x3000
auipc x24, 0x4000
auipc x25, 0x5000
auipc x26, 0x6000
auipc x27, 0x7000
auipc x28, 0x8000

lui x1, 0xFFFFF
lui x2, 0x00000
lui x3, 0xAAAAA
lui x4, 0x55555

#==============================================================================
# Section 6: More Arithmetic Combinations (60 instructions)
#==============================================================================
add x21, x21, x1
add x22, x22, x2
add x23, x23, x3
add x24, x24, x4
add x25, x25, x5
add x26, x26, x6
add x27, x27, x7
add x28, x28, x8

sub x21, x21, x1
sub x22, x22, x2
sub x23, x23, x3
sub x24, x24, x4
sub x25, x25, x5
sub x26, x26, x6
sub x27, x27, x7
sub x28, x28, x8

and x21, x21, x20
and x22, x22, x19
and x23, x23, x18
and x24, x24, x17
or x25, x25, x16
or x26, x26, x15
or x27, x27, x14
or x28, x28, x13

xor x21, x21, x10
xor x22, x22, x11
xor x23, x23, x12
xor x24, x24, x13
xor x25, x25, x14
xor x26, x26, x15
xor x27, x27, x16
xor x28, x28, x17

add x1, x1, x21
add x2, x2, x22
add x3, x3, x23
add x4, x4, x24
sub x5, x5, x25
sub x6, x6, x26
sub x7, x7, x27
sub x8, x8, x28

slt x21, x1, x2
slt x22, x3, x4
slt x23, x5, x6
slt x24, x7, x8
sltu x25, x9, x10
sltu x26, x11, x12
sltu x27, x13, x14
sltu x28, x15, x16

and x1, x1, x2
and x3, x3, x4
and x5, x5, x6
and x7, x7, x8
or x9, x9, x10
or x11, x11, x12
or x13, x13, x14
or x15, x15, x16

#==============================================================================
# Section 7: More Immediate Operations (40 instructions)
#==============================================================================
addi x1, x1, 10
addi x2, x2, 20
addi x3, x3, 30
addi x4, x4, 40
addi x5, x5, 50
addi x6, x6, 60
addi x7, x7, 70
addi x8, x8, 80

xori x21, x1, 0x12
xori x22, x2, 0x34
xori x23, x3, 0x56
xori x24, x4, 0x78
xori x25, x5, 0x9A
xori x26, x6, 0xBC
xori x27, x7, 0xDE
xori x28, x8, 0xF0

ori x1, x1, 0x01
ori x2, x2, 0x02
ori x3, x3, 0x03
ori x4, x4, 0x04
ori x5, x5, 0x05
ori x6, x6, 0x06
ori x7, x7, 0x07
ori x8, x8, 0x08

andi x21, x21, 0xFF
andi x22, x22, 0xFF
andi x23, x23, 0xFF
andi x24, x24, 0xFF
andi x25, x25, 0xFF
andi x26, x26, 0xFF
andi x27, x27, 0xFF
andi x28, x28, 0xFF

slti x1, x1, 100
slti x2, x2, 200
slti x3, x3, 300
slti x4, x4, 400
sltiu x5, x5, 500
sltiu x6, x6, 600
sltiu x7, x7, 700
sltiu x8, x8, 800

#==============================================================================
# Section 8: Complex Shift Patterns (30 instructions)
#==============================================================================
slli x21, x1, 1
slli x22, x2, 2
slli x23, x3, 3
slli x24, x4, 4
slli x25, x5, 5
slli x26, x6, 6
slli x27, x7, 7
slli x28, x8, 8

srli x21, x21, 1
srli x22, x22, 2
srli x23, x23, 3
srli x24, x24, 4
srli x25, x25, 5
srli x26, x26, 6
srli x27, x27, 7
srli x28, x28, 8

srai x1, x1, 1
srai x2, x2, 1
srai x3, x3, 1
srai x4, x4, 1
srai x5, x5, 2
srai x6, x6, 2
srai x7, x7, 2
srai x8, x8, 2

sll x21, x1, x2
srl x22, x3, x4
sra x23, x5, x6
sll x24, x7, x8
srl x25, x9, x10
sra x26, x11, x12

#==============================================================================
# Section 9: Mixed Operations (50 instructions)
#==============================================================================
add x1, x1, x2
sub x3, x4, x5
and x6, x7, x8
or x9, x10, x11
xor x12, x13, x14
sll x15, x16, x17
srl x18, x19, x20
add x21, x22, x23

addi x1, x1, 15
xori x2, x2, 0xAA
ori x3, x3, 0x55
andi x4, x4, 0xF0
slli x5, x5, 3
srli x6, x6, 2
srai x7, x7, 1
slti x8, x8, 50

sub x21, x1, x2
add x22, x3, x4
xor x23, x5, x6
and x24, x7, x8
or x25, x9, x10
slt x26, x11, x12
sltu x27, x13, x14
add x28, x15, x16

lui x1, 0x10000
auipc x2, 0x1000
addi x3, x3, 100
xori x4, x4, 0xFF
ori x5, x5, 0x0F
andi x6, x6, 0xF0
slli x7, x7, 4
srli x8, x8, 3

add x21, x21, x22
sub x22, x22, x23
and x23, x23, x24
or x24, x24, x25
xor x25, x25, x26
sll x26, x26, x1
srl x27, x27, x2
sra x28, x28, x3

addi x1, x0, 111
addi x2, x0, 222
addi x3, x0, 333
addi x4, x0, 444
add x5, x1, x2
add x6, x3, x4
sub x7, x6, x5
and x8, x5, x6

#==============================================================================
# Section 10: Final Computations (40 instructions)
#==============================================================================
add x21, x1, x2
add x22, x3, x4
add x23, x5, x6
add x24, x7, x8
add x25, x9, x10
add x26, x11, x12
add x27, x13, x14
add x28, x15, x16

sub x21, x20, x21
sub x22, x19, x22
sub x23, x18, x23
sub x24, x17, x24
sub x25, x16, x25
sub x26, x15, x26
sub x27, x14, x27
sub x28, x13, x28

and x21, x21, x1
and x22, x22, x2
and x23, x23, x3
and x24, x24, x4
or x25, x25, x5
or x26, x26, x6
or x27, x27, x7
or x28, x28, x8

xor x21, x21, x28
xor x22, x22, x27
xor x23, x23, x26
xor x24, x24, x25
xor x25, x25, x24
xor x26, x26, x23
xor x27, x27, x22
xor x28, x28, x21

addi x1, x1, 1
addi x2, x2, 2
addi x3, x3, 3
addi x4, x4, 4
addi x5, x5, 5
addi x6, x6, 6
addi x7, x7, 7
addi x8, x8, 8

#==============================================================================
# Halt
#==============================================================================
halt:
    slti x0, x0, -256
