# Sim B — Custom RISC-V Instruction vs MMIO Loads for ITCH Market Data

Three firmware paths, same CPU build, same testbench. Each path processes one
ITCH 5.0 Add Order packet, decides whether to "buy" based on `(msg_type=='A')
&& (price > 0x10000) && (shares > 100)`, and writes the boolean decision to a
known memory location. The packet always yields decision=1.

Cycle counts come from the testbench monitor between segment-marker
instructions (`slti x0,x0,1` / `slti x0,x0,2`), so per-path setup and the
trailing halt are excluded. Clock period is 1850 ps (`options.json:clock`).

## Numbers

| Path | Firmware                  | Segment time (ps) | Cycles | IPC    | Commits in segment |
|------|---------------------------|------------------:|-------:|-------:|-------------------:|
| 1    | Software ITCH parse       |           432,900 |    234 | 0.175  |                 90 |
| 2    | MMIO loads (`lw`)         |           194,250 |    105 | 0.152  |                 65 |
| 3    | `fetch_trade` (custom-1)  |           109,150 |     59 | 0.237  |                 63 |

Speedups: path 2 is 2.23x faster than path 1; path 3 is 1.78x faster than
path 2 and 3.97x faster than path 1.

## What each path does

### Path 1 — `itch_swparse.c`
The raw 36-byte Add Order packet sits in `.data` as `volatile uint8_t`. The
firmware does byte-by-byte big-endian assembly of the `shares` and `price`
fields, compares them, and stores the decision. Pure software, no parser.
All 36 packet bytes must traverse the d-cache.

### Path 2 — `itch_mmio.c`
Eight pre-parsed fields sit at fixed offsets, simulating the output of a
hardware ITCH parser that has written results into a memory-mapped BRAM.
Firmware does three `lw` instructions (for msg_type, shares, price), no
byte-swapping. Still routes through the d-cache.

### Path 3 — `itch_custom.c` + RTL changes
New I-type instruction `fetch_trade rd, imm[2:0]` at opcode `0x2b`
(custom-1). Decoded as `FU_FETCH_TRADE` and routed to a dedicated reservation
station + functional unit (modeled on the `mul`/`mul_rs` pattern). The FU
wraps an `xpm_memory_sdpram` BRAM primitive (8 entries x 32 wide,
common-clock, registered read). The FU output shares the `cdb_mul_div` lane;
a 4-deep `trade_result_buffer` queue handles arbiter contention with mul/div
(unused in HFT workload). Three `fetch_trade`s replace the three `lw`s of
path 2.

## Why the cycle count is identical to the previous LUT-based design

The earlier proof-of-concept used a combinational 8-entry LUT array inside
`alu.sv`. Replacing it with an XPM_MEMORY BRAM trades a combinational read
for a registered read — but the OoO core's pipeline already had a registered
stage at the ALU RS (`rs_alu_ready_entry`). Moving the register from the RS
into the BRAM read path leaves the total dispatch-to-CDB latency unchanged
at 2 cycles. The new design therefore matches the old cycle count exactly
while replacing the LUT with a real BRAM primitive that Vivado synthesizes
to a BRAM18.

Functional correctness was confirmed by a hang-on-wrong test (firmware
enters an infinite loop if any BRAM read returns an unexpected value); the
test halted normally, proving `mtype=0x41`, `shares=1000`, `price=100000`
on every read.

## Why path 3 beats path 2

Same commit count (within 2 instructions), same trade-decision branches, but
each parsed-field fetch goes through the d-cache in path 2 vs the dedicated
BRAM-backed FU in path 3. The 46-cycle delta is the d-cache + LSU pipeline
cost of three `lw`s minus the cost of three `fetch_trade`s. IPC also rises
(0.152 -> 0.237) because the fetch_trade FU issues without the LSQ
serialization that loads incur.

## How to reproduce

```bash
cd ~/SP26/ie497/riscv-cpu
source ./setup_env.sh            # Synopsys 2024 + Xilinx 2025.1 + riscv toolchain
cd sim
# Sim build with Spike functional reference disabled (Spike doesn't know
# the custom-1 opcode and would otherwise trap on path 3).
make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" vcs/top_tb

for prog in itch_swparse.c itch_mmio.c itch_custom.c; do
  echo "== $prog =="
  make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" \
       run_vcs_top_tb PROG=../testcode/sim_b/$prog 2>&1 \
    | grep -E 'Segment|Total Commits'
done
```

The `Segment Time` printed by the monitor divided by 1850 ps gives the cycle
count in the table above.

## RTL change summary (path 3 only)

- `pkg/types.sv`:
  - Added `op_custom1 = 7'b0101011` to `rv32i_opcode`.
  - Added `FU_FETCH_TRADE = 3'b011` to `fu_flags`.
  - Added `FT_RS_SIZE = 4` localparam.
  - Added `rs_fetch_trade_entry_t` and `fu_fetch_trade_pkt` structs.
  - Removed earlier `is_trade` field from `decode_packet_t`,
    `rename_packet_t`, `rs_alu_entry_t`, `fu_alu_pkt` (no longer needed —
    `fu_flag == FU_FETCH_TRADE` drives routing).
- `hdl/core/decode.sv`: `op_custom1` case sets `fu_flag = FU_FETCH_TRADE`.
- `hdl/core/rename.sv`: passes `fu_flag` through (no new fields).
- `hdl/core/dispatch.sv`: new `FU_FETCH_TRADE` case routes to `rs_ft_enq`.
- `hdl/execution/fetch_trade.sv` (new): wraps `xpm_memory_sdpram`, packet
  pipeline aligned to BRAM read latency, emits `cdb_mul_div_pkt`.
- `hdl/execution/fetch_trade_rs.sv` (new): minimal FIFO RS, no wakeup
  machinery (custom-1 has no source operands).
- `hdl/execution/alu.sv`: reverted to the original A-grade form (LUT array
  and `is_trade` branch removed).
- `hdl/core/cpu.sv`: instantiates `fetch_trade` FU + `fetch_trade_rs`, adds
  `trade_result_buffer` queue, extends mul/div arbiter to 5-way priority
  (DIV > mul_buf > MUL > trade_buf > TRADE).
- `setup_env.sh`: loads `xilinx/2025.1` module and exports `XILINX_VIVADO`.
- `sim/Makefile`: adds `XPM_INCDIR` and compiles `xpm_memory.sv` from the
  Vivado install.
- `sim/xprop.config`: `xpropOff` for the XPM modules (Xilinx IP uses
  non-instrumentable statements).
- `sim/vcs_warn.config`: `lint=none` for the XPM modules (suppresses
  benign ULCO warnings from XPM's parameter string comparisons).

The CPU is read-only outside these edits. No changes to ROB, RAT, RRAT,
freelist, LSQ, cache, or any existing RS module — the new FU integrates
through the existing CDB infrastructure by sharing the mul/div lane.

## Caveats

- Spike DPI checking is disabled for these runs because Spike doesn't model
  custom-1. All three paths are run with the same testbench build to keep
  the comparison fair. Correctness on path 3 was verified by an explicit
  hang-on-wrong-value test in the firmware (sim halts iff all three reads
  returned the expected values).
- BRAM contents are initialized via `MEMORY_INIT_PARAM` to the same values
  paths 1 and 2 use (`msg_type=0x41`, `shares=1000`, `price=100000`). In a
  deployed design Port A of the SDPRAM would be driven by the parser; here
  Port A is tied off.
- The cycle counts exclude `_start` and the trailing halt — the segment
  markers gate exactly the parse + decision + store, which is the
  apples-to-apples comparison.
- Path 2 vs path 3 isn't penalized by extra cache misses: by the time we
  reach the segment, the d-cache has already been touched by stack
  operations, so path 2's three loads largely hit. The 46-cycle delta is
  pipeline / LSQ latency, not cold-miss penalty.
