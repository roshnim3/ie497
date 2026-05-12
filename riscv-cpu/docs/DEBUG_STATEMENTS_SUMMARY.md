# Debug Statements Summary

## Files Modified

### Core Pipeline Stages
1. **hdl/core/fetch.sv** - Added formatted debug for instruction fetch, queue operations, and flushes
2. **hdl/core/decode.sv** - Added formatted debug for instruction decode with operation details
3. **hdl/core/rename.sv** - Added formatted debug for register renaming and physical register allocation
4. **hdl/core/dispatch.sv** - Added formatted debug for reservation station dispatch and CDB bypass
5. **hdl/core/rob.sv** - Enhanced debug for enqueue, commit, CDB broadcasts, and flushes
6. **hdl/core/rat.sv** - Added formatted debug for RAT updates, CDB readiness, and flushes
7. **hdl/core/freelist.sv** - Added formatted debug for physical register allocation/freeing

### Execution Units
8. **hdl/execution/lsq.sv** - Enhanced debug for LSQ operations, dependencies, and memory ordering
9. **hdl/execution/alu_rs.sv** - Added formatted debug for reservation station operations
10. **hdl/execution/prf.sv** - Added formatted debug for physical register file writes

### Memory Subsystem
11. **hdl/memory/ppcache.sv** - Enhanced debug with formatted output for cache hits, misses, and state transitions

## Debug Format Features

All debug statements now use a consistent **box format** with:
- ┌─┬─┐ borders for visual clarity
- [MODULE] prefix to identify source
- @time timestamp for event correlation
- Organized field display with clear labels
- Highlighted critical events with *** markers

### Example Output:
```
┌─────────────────────────────────────────────────────────────────────────┐
│ [FETCH] @1000: Instruction Fetched & Enqueued                           │
├─────────────────────────────────────────────────────────────────────────┤
│  PC:           0xa0001000                                               │
│  Instruction:  0x00a58593                                               │
│  PC_next:      0xa0001004                                               │
│  Branch Pred:  NOT_TAKEN                                                │
│  Queue Full:   0                                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

## Key Improvements

1. **Consistent Formatting**: All modules use the same box-drawing format
2. **Easy Visual Parsing**: Bordered boxes make it easy to spot events in large logs
3. **Complete Coverage**: Every major pipeline stage and functional unit has debug output
4. **Event Highlighting**: Critical events (commits, flushes, cache operations) marked with ***
5. **Correlation Support**: ROB index and time stamps help trace instructions through pipeline
6. **Field Organization**: All related information grouped in clear, labeled fields

## Usage

Simply run your simulation as normal:
```bash
cd /home/suvids2/out_of_touch/mp_ooo/sim
make run_vcs_top_tb PROG=../testcode/simple_load_test.s
```

The debug output will automatically appear in the console/log files.

## Documentation

See **DEBUG_OUTPUT_GUIDE.md** for:
- Complete list of traced events
- How to read the debug output
- Filtering techniques
- Tips for debugging common issues
