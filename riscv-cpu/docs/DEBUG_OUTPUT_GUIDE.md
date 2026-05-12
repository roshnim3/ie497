# Debug Output Guide

## Overview
Comprehensive debug statements have been added to all major modules in the out-of-order processor. All debug output uses a consistent, easy-to-read box format for clarity.

## Debug Output Format

All debug messages use a bordered box format for easy visual separation:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ [MODULE] @time: Event Description                                       │
├─────────────────────────────────────────────────────────────────────────┤
│  Field Name:   Value                                                    │
│  Field Name:   Value                                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Modules with Debug Statements

### 1. FETCH Stage (`hdl/core/fetch.sv`)
**Events Traced:**
- Instruction fetched and enqueued
- Dequeuing to decode stage
- Pipeline flush

**Key Information:**
- PC value
- Instruction word
- Branch prediction
- Queue status
- Downstream readiness signals

### 2. DECODE Stage (`hdl/core/decode.sv`)
**Events Traced:**
- Instruction decoded

**Key Information:**
- PC and instruction
- Opcode
- Source and destination registers
- Immediate value
- Functional unit assignment
- Operation type (ALU/Branch/Memory)

### 3. RENAME Stage (`hdl/core/rename.sv`)
**Events Traced:**
- Register renaming

**Key Information:**
- Architectural register mappings
- Physical register mappings
- Register ready status
- ROB index assignment
- Allocation requests

### 4. DISPATCH Stage (`hdl/core/dispatch.sv`)
**Events Traced:**
- Dispatching to reservation stations
- Pipeline flush

**Key Information:**
- Target functional unit
- Physical register mappings and ready bits
- CDB bypass detection
- Reservation station status

### 5. ROB (Reorder Buffer) (`hdl/core/rob.sv`)
**Events Traced:**
- Entry enqueue
- Instruction commit
- CDB broadcasts (ALU/BR, MUL/DIV, MEM)
- Branch misprediction flush

**Key Information:**
- ROB index
- PC and instruction
- Result values
- ROB occupancy
- Branch prediction vs actual
- Commit order

### 6. LSQ (Load-Store Queue) (`hdl/execution/lsq.sv`)
**Events Traced:**
- Entry enqueue
- Address/data calculation updates
- Store issue (at ROB head)
- Load issue (independent loads)
- Dependency blocking

**Key Information:**
- Memory operation type
- Address and data values
- ROB index
- Dependencies
- Queue occupancy

### 7. ALU Reservation Station (`hdl/execution/alu_rs.sv`)
**Events Traced:**
- Entry enqueue
- Ready entry issue

**Key Information:**
- Physical register addresses
- Ready status
- ALU operation
- Reservation station occupancy

### 8. Memory Functional Unit (`hdl/execution/mem.sv`)
**Events Traced:**
- Request latching
- Cache request sending
- Cache response

**Key Information:**
- Memory operation type (load/store)
- Address
- Data values
- ROB index

### 9. Physical Register File (`hdl/execution/prf.sv`)
**Events Traced:**
- Register writes from ALU/BR
- Register writes from MUL/DIV
- Register writes from MEM

**Key Information:**
- Physical register number
- Written value

### 10. Data Cache (`hdl/memory/ppcache.sv`)
**Events Traced:**
- Stage 1 latch (new request)
- Cache hit (read/write)
- Cache miss
- State transitions (MISS_START, WRITEBACK, ALLOCATE, etc.)

**Key Information:**
- Address
- Hit/miss status
- Way number
- Read/write operation
- State machine transitions
- Data values

### 11. Freelist (`hdl/core/freelist.sv`)
**Events Traced:**
- Physical register allocation
- Physical register freeing
- Flush and rebuild from RRAT

**Key Information:**
- Allocated/freed register number
- Full/empty status

### 12. RAT (Register Alias Table) (`hdl/core/rat.sv`)
**Events Traced:**
- New register mapping
- CDB updates (register ready)
- Flush and restore from RRAT

**Key Information:**
- Architectural to physical register mapping
- Old and new physical registers
- Ready status changes

## Reading the Debug Output

### Typical Instruction Flow:

1. **FETCH**: Instruction fetched from memory
2. **DECODE**: Instruction decoded, registers identified
3. **RENAME**: Architectural registers mapped to physical registers
4. **DISPATCH**: Instruction dispatched to appropriate reservation station
5. **RS**: Entry waits until operands ready
6. **FU**: Functional unit executes when operands available
7. **CDB**: Result broadcast on Common Data Bus
8. **ROB**: ROB entry marked ready
9. **PRF**: Physical register file updated
10. **COMMIT**: Instruction commits at ROB head

### Special Events:

- **FLUSH**: Branch misprediction causes pipeline flush
  - Look for "*** FLUSH ***" markers
  - ROB, RAT, and Freelist all print flush messages
  
- **CACHE MISS**: Data cache miss causes stall
  - State machine transitions through MISS_START → WRITEBACK (if dirty) → ALLOCATE → ALLOC_IDLE
  
- **STORE ORDERING**: Stores only issue when at ROB head
  - Look for "*** ISSUING STORE AT ROB HEAD ***"
  
- **LOAD DEPENDENCY**: Loads blocked by older stores
  - Look for "LOAD BLOCKED" messages in LSQ

## Filtering Debug Output

To focus on specific modules, you can grep the output:

```bash
# Show only ROB activity
make run_vcs_top_tb PROG=../testcode/test.s 2>&1 | grep "\[ROB\]"

# Show only cache activity
make run_vcs_top_tb PROG=../testcode/test.s 2>&1 | grep "\[PPCACHE\]"

# Show only memory operations
make run_vcs_top_tb PROG=../testcode/test.s 2>&1 | grep -E "\[LSQ\]|\[MEM_FU\]|\[PPCACHE\]"

# Show pipeline progression for a specific PC
make run_vcs_top_tb PROG=../testcode/test.s 2>&1 | grep "0xa0001000"
```

## Debug Tips

1. **Look for box headers** to quickly identify module events
2. **Time stamps** (`@time`) help correlate events across modules
3. **ROB Index** is a unique identifier that follows an instruction through the pipeline
4. **Physical register numbers** (P0-P63) track data dependencies
5. **"***" markers** highlight critical events (commits, flushes, cache operations)

## Performance Notes

These debug statements are for debugging only. They will:
- Significantly slow down simulation
- Generate large amounts of output
- Should be disabled for synthesis or performance testing

To reduce output, you can comment out specific `$display` statements or entire debug blocks.
