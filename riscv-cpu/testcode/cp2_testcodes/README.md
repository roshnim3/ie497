# CP2 Test Suite Documentation

## cp2_reservation_station_test.s
TEST 1: Fill MUL RS by issuing 8 independent multiplies (fills RS) then 8 more (overflow)
TEST 2: Fill DIV RS by issuing 8 independent divides (fills RS) then 8 more (overflow)
TEST 3: Fill ALU RS by issuing 8 independent ALU ops (fills RS) then 12 more (overflow)
TEST 4: Fill all RS simultaneously with mixed MUL/DIV/ALU operations
TEST 5: Fill RS while long dependency chain is in flight
TEST 6: Rapid issue/completion to maintain RS pressure
TEST 7: Alternate dependent/independent ops while RS full
TEST 8: Fill all 24 RS slots (8 MUL + 8 DIV + 8 ALU) then issue overflow operations

## cp2_dependency_stress_test.s
TEST 1: 15-stage RAW dependency chain on single register
TEST 2: Multiple parallel dependency chains (3 chains of 10 ops each)
TEST 3: 6 WAW hazards (6 writes to same destination register)
TEST 4: 4-level dependency tree with multiple sources
TEST 5: Alternating long/short latency operations in dependency chain
TEST 6: Diamond dependency pattern (split into 3 paths, then reconverge)
TEST 7: Cascading WAW hazards with dependencies between writes
TEST 8: Binary tree dependency pattern (8 operations forming tree)
TEST 9: Complex circular-like dependency web
TEST 10: Dependency chain using all operation types (MUL, DIV, ALU)
TEST 11: Register reuse patterns (same register as source and destination)
TEST 12: 32-stage maximum depth dependency chain
TEST 13: Cross-functional-unit dependencies (MUL→DIV→ALU→MUL forwarding)
TEST 14: Dependencies with structural hazards (RS/ROB full conditions)

## cp2_comprehensive_test.s
TEST 1: ADDI with positive, negative, zero, max immediates
TEST 2: SLTI signed comparisons with various immediates
TEST 3: SLTIU unsigned comparisons
TEST 4: XORI with various immediate patterns
TEST 5: ORI with various immediate patterns
TEST 6: ANDI with various immediate patterns
TEST 7: SLLI shifts by 0, 1, 15, 31
TEST 8: SRLI shifts by 0, 1, 15, 31
TEST 9: SRAI shifts by 0, 1, 15, 31
TEST 10: LUI with 0, max, various patterns
TEST 11: ADD with positive, negative, zero operands
TEST 12: SUB with positive, negative, zero operands
TEST 13: SLT signed comparisons
TEST 14: SLTU unsigned comparisons
TEST 15: AND, OR, XOR logical operations
TEST 16: SLL, SRL, SRA register shifts
TEST 17: MUL basic multiplication
TEST 18: MULH signed high multiplication with extreme values
TEST 19: MULHSU signed×unsigned high multiplication
TEST 20: MULHU unsigned high multiplication
TEST 21: DIV signed division including DIV-0
TEST 22: DIVU unsigned division including DIV-0
TEST 23: REM signed remainder including REM-0
TEST 24: REMU unsigned remainder including REM-0
TEST 25: RAW dependency chains
TEST 26: WAW hazards
TEST 27: Extreme value testing (0x80000000, 0x7FFFFFFF, 0xFFFFFFFF)

## cp2_ooo_stress_test.s
TEST 1: 5 independent long multiplies to test parallel execution
TEST 2: 3 dependent multiplies in chain with forwarding
TEST 3: Diamond dependency (1 op splits to 3, reconverges to 1)
TEST 4: Interleaved independent and dependent operations
TEST 5: High register pressure (uses x1-x31)
TEST 6: Multiple WAW hazards (5 writes to same destination)
TEST 7: 4 independent divides in parallel
TEST 8: Back-to-back dependent multiplies (MUL→MUL forwarding)
TEST 9: Complex mixed dependency graph (MUL/DIV/ALU interleaved)
TEST 10: Division by zero and multiplication by zero cases

## cp2_edge_cases_test.s
TEST 1: DIV by zero (result = -1)
TEST 2: DIVU by zero (result = 0xFFFFFFFF)
TEST 3: REM by zero (result = dividend)
TEST 4: REMU by zero (result = dividend)
TEST 5: DIV overflow 0x80000000/-1 (result = 0x80000000)
TEST 6: REM overflow 0x80000000/-1 (result = 0)
TEST 7: Signed multiplication extremes (0x80000000 × 0x80000000)
TEST 8: Unsigned multiplication extremes (0xFFFFFFFF × 0xFFFFFFFF)
TEST 9: MULHSU edge cases (signed × unsigned extremes)
TEST 10: Shift by 0, 31, >31 (wrapped amounts)
TEST 11: x0 register as source and destination
TEST 12: Immediate value limits (-2048, 2047)
TEST 13: LUI with 0, 0xFFFFF, various patterns
TEST 14: SLT/SLTU with extreme values (0x80000000, 0x7FFFFFFF)
TEST 15: Remainder sign rules (follows dividend)
TEST 16: All-ones pattern (0xFFFFFFFF) through all operations

## cp2_clear_ooo_demo.s
TEST 1: 1 long multiply followed by 10 independent adds (adds complete first)
TEST 2: 1 long divide followed by 10 independent operations
TEST 3: 3 long multiplies with 3 independent ops between each
TEST 4: Waterfall of decreasing latency ops (long to short)
TEST 5: 3 independent multiply chains executing in parallel
TEST 6: 1 long multiply followed by 20 independent operations
TEST 7: 3 dependent multiplies with independent ops issued between (slip through)
TEST 8: Diamond dependency with long operations on split paths

## Usage
```bash
cd mp_ooo/sim
make run_vcs_top_tb PROG=../testcode/cp2_testcodes/cp2_comprehensive_test.s
make run_vcs_top_tb PROG=../testcode/cp2_testcodes/cp2_edge_cases_test.s
make run_vcs_top_tb PROG=../testcode/cp2_testcodes/cp2_reservation_station_test.s
make run_vcs_top_tb PROG=../testcode/cp2_testcodes/cp2_dependency_stress_test.s
make run_vcs_top_tb PROG=../testcode/cp2_testcodes/cp2_ooo_stress_test.s
make run_vcs_top_tb PROG=../testcode/cp2_testcodes/cp2_clear_ooo_demo.s
```

## RISC-V Spec Requirements
Division by zero: DIV x/0 = -1, DIVU x/0 = 0xFFFFFFFF, REM x/0 = x, REMU x/0 = x
Division overflow: DIV 0x80000000/-1 = 0x80000000, REM 0x80000000/-1 = 0
Reservation stations: 8 entries deep per functional unit (MUL, DIV, ALU)
