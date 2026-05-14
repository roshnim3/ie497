# Sim B — Custom RISC-V Instruction vs MMIO Loads for ITCH Market Data

Three firmware paths, same CPU build, same testbench. Each path processes
ITCH 5.0 Add Order packets, decides whether to "buy" based on
`(msg_type=='A') && (price > 0x10000) && (shares > 100)`, and writes the
boolean decision to a known memory location.

Cycle counts come from the testbench monitor between segment-marker
instructions (`slti x0,x0,1` / `slti x0,x0,2`), so per-path setup and the
trailing halt are excluded. Clock period is 1850 ps (`options.json:clock`).

## Single-shot numbers (one packet, cold start)

| Path | Firmware                  | Segment time (ps) | Cycles | IPC    | Commits |
|------|---------------------------|------------------:|-------:|-------:|--------:|
| 1    | Software ITCH parse       |           432,900 |    234 | 0.175  |      90 |
| 2    | MMIO loads (`lw`)         |           194,250 |    105 | 0.152  |      65 |
| 3    | `fetch_trade` (custom-1)  |           109,150 |     59 | 0.237  |      63 |

Single-shot speedups: path 2 is 2.23x faster than path 1; path 3 is 1.78x
faster than path 2 and 3.97x faster than path 1. **These are cold-start
numbers for one packet.** They overstate sustained per-event speedup
because the segment includes setup latency that gets amortized once the
workload streams. See the scaling sweep below for steady-state numbers.

## Scaling sweep — steady-state per-event throughput

Same three firmwares, wrapped in a loop of `ITER` iterations (sources:
`itch_swparse_loop.c`, `itch_mmio_loop.c`, `itch_custom_loop.c`). Each
iteration re-runs the parse + decide + accumulate. The decision counter is
stored once at end-of-segment. Repro: `testcode/sim_b/run_scaling.sh` emits
`scaling_results.csv`.

| Path | ITER=1 | ITER=10 | ITER=100 | ITER=1000 |
|------|-------:|--------:|---------:|----------:|
| SW parse      |  226 cyc |  1,552 cyc |  5,697 cyc | 55,197 cyc |
| MMIO `lw`     |   67 cyc |    565 cyc |  2,983 cyc | 29,083 cyc |
| `fetch_trade` |   36 cyc |    511 cyc |  2,630 cyc | 26,030 cyc |

Per-event cost (slope between ITER=100 and ITER=1000, the steady-state
region):

| Path | cycles/event | speedup vs SW | speedup vs MMIO |
|------|-------------:|--------------:|----------------:|
| SW parse      | **55.0** | 1.00x | — |
| MMIO `lw`     | **29.0** | 1.90x | 1.00x |
| `fetch_trade` | **26.0** | 2.12x | **1.12x** |

IPC at ITER=1000:

| Path | IPC | Commits/event |
|------|----:|--------------:|
| SW parse      | 0.65 | 36 |
| MMIO `lw`     | 0.34 | 10 |
| `fetch_trade` | 0.38 | 10 |

## Single-shot vs steady-state (the important comparison)

| Measurement | SW | MMIO | `fetch_trade` | Custom-vs-MMIO speedup |
|-------------|---:|-----:|--------------:|----------------------:|
| Cold-start cycles (ITER=1, single-shot) | 234 | 105 | 59 | **1.78x** |
| Steady-state cycles/event (slope)        |  55 |  29 | 26 | **1.12x** |

**The single-shot 1.78x speedup over MMIO collapses to 1.12x under
sustained load.** This is the honest finding the report should lead with.

### Why this happens

- **MMIO under load benefits from LSQ pipelining + warm d-cache.** The
  first `lw` pays the latency; subsequent `lw`s to the same address
  pipeline through the LSU and complete one per cycle or two. The 105-cycle
  single-shot was MMIO's cold-startup number, not its steady-state.
- **`fetch_trade` was already near-optimal at ITER=1** (2-cycle FU
  latency, no LSQ). It has less headroom to gain from pipelining because
  it was already pipelined.
- **The IPC trajectory confirms this**: at ITER=1, MMIO IPC is 0.22,
  custom is 0.36. At ITER=1000, MMIO is 0.34, custom is 0.38. The gap
  closes because MMIO has more room to grow.

### What's still defensible for the report

1. **`fetch_trade` is the fastest path in every measurement** — 2.12x
   faster than SW parse, 1.12x faster than MMIO, in steady-state.
2. **Per-event savings: 3 cycles vs MMIO, 29 cycles vs SW parse.** At the
   CPU's eventual synthesized frequency, sustained over a trading day's
   event rate, the 3-cycle/event MMIO delta is the relevant figure for any
   wall-clock claim.
3. **The cycles/event slope is the architecturally invariant number.** The
   single-shot 1.78x was an artifact of how much startup overhead got
   divided into how few events. The scaling sweep separates startup from
   per-event cost.
4. **`fetch_trade` reaches steady-state IPC almost immediately** (0.36 at
   ITER=1 vs 0.38 at ITER=1000), while MMIO and SW parse have to warm up.
   For a low-latency claim, predictable per-event cost from the first
   event is a real advantage — not just average throughput.

### Honest framing for the writeup

> "At sustained event rates, `fetch_trade` reaches steady-state at
> 26 cycles/event vs MMIO's 29 — a 12% per-event improvement.
> The 2-cycle FU bypass of the LSQ remains the fastest path and reaches
> steady-state from the first event with no warmup, but the headline
> single-shot 1.78x speedup over MMIO is a cold-start measurement that
> compresses to 1.12x once the LSQ is pipelined."

## Top-of-book (BBO) benchmark — realistic decision logic

Sources: `itch_swparse_bbo.c`, `itch_mmio_bbo.c`, `itch_custom_bbo.c`.
Each iteration reads four fields (msg_type, side, shares, price) and
maintains best_bid / best_ask state, conditionally incrementing
buy_decisions when the spread tightens with sufficient shares. State
carries across iterations (local register-allocated; final values stored
once at segment end).

`ITER=1000` for all three paths. Same packet on every iteration (Port A
of the BRAM is tied off in this delta), so best_bid and best_ask
stabilize after iteration 1 — the per-iteration *work* is still
representative (4 reads + 4-5 comparisons + 2-3 conditional branches),
but the conditional updates do not fire in steady state. Treat this as a
per-event throughput benchmark, not a varied-data benchmark.

| Path                | Cycles (ITER=1000) | IPC   | Commits | Cycles/event |
|---------------------|-------------------:|------:|--------:|-------------:|
| SW parse BBO        |             57,272 | 0.577 |  33,106 |     **57.3** |
| MMIO BBO            |             35,215 | 0.341 |  12,094 |     **35.2** |
| `fetch_trade` BBO   |             31,169 | 0.386 |  12,092 |     **31.2** |

Per-event speedups:

| | vs SW | vs MMIO |
|-|------:|--------:|
| MMIO BBO         | 1.63× | — |
| `fetch_trade` BBO | 1.83× | **1.13×** |

## Decision-complexity comparison (trivial loop vs BBO)

| Benchmark         | SW c/ev | MMIO c/ev | Custom c/ev | Custom-vs-MMIO |
|-------------------|--------:|----------:|------------:|---------------:|
| Trivial loop      |  55.0   |   29.0    |   26.0      |    1.12×       |
| BBO state machine |  57.3   |   35.2    |   31.2      |    1.13×       |

**Architectural reading**: the custom-vs-MMIO speedup is **stable at
~1.12-1.13×** independent of how much decision logic surrounds the field
reads. This is because both paths run the same decision code (identical
ALU/branch ops); the only delta is the per-event parse savings.

- Absolute cycles saved by `fetch_trade` vs MMIO: **~4 cycles/event,
  regardless of decision complexity**. This is the architecturally
  invariant headroom.
- Relative speedup is a function of how parse-dominated the workload is.
  More decision logic → smaller relative speedup over MMIO (parse cost
  shrinks as a fraction of total). More parse-dominated → larger relative
  speedup.

The custom-vs-SW speedup compresses from 2.12× (trivial) to 1.83× (BBO)
for the opposite reason: SW parse's byte-assembly cost is fixed-per-event
but a smaller fraction of BBO's heavier per-event workload.

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
