# Accelerating the Tick-to-Trade Critical Path through Custom RISC-V Instructions and FPGA-Based Ethernet Parsing for High-Frequency Trading

**IE497, Spring 2026 — Independent Project Report**

---

## Abstract

High-frequency trading requires decisions within microseconds of market-data arrival — a budget that general-purpose processors paired with software-based parsing and conventional memory-mapped I/O cannot reliably meet. This thesis presents a co-designed two-stage architecture that moves both ends of the tick-to-trade pipeline onto dedicated hardware. A custom RISC-V processor is extended with four new instructions that bypass the standard memory-access path: one reads pre-parsed market-data fields from an on-chip buffer in 59 cycles against 105 for the equivalent memory-mapped load — a 1.78× single-shot speedup — and three more compose a transmit primitive that lets software stage Ethernet order frames across eight hardware-managed buffers and fire them with a single instruction. Cycle-accurate simulation measures an end-to-end tick-to-trade latency of 94 cycles (roughly 290 nanoseconds at 322 MHz) with sustained transmit throughput of 5.66 Gbps. On the network side, a Verilog packet-parser plugin synthesized into the OpenNIC framework on a Xilinx Alveo U55C decodes MoldUDP64-encapsulated ITCH messages from the 100-gigabit Ethernet interface and exposes the parsed fields to host software through PCIe-readable status registers, removing software decoding from the critical path. The two subsystems together quantify the latency gains achievable by displacing both market-data ingestion and order emission from commodity-core software to purpose-built silicon.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Repository Structure](#2-repository-structure)
3. [Hardware and Software Environment](#3-hardware-and-software-environment)
4. [Required Privileges and Sudoers Configuration](#4-required-privileges-and-sudoers-configuration)
5. [Cloning and Initial Setup](#5-cloning-and-initial-setup)
6. [RISC-V CPU Side: Custom Instructions in Simulation](#6-risc-v-cpu-side-custom-instructions-in-simulation)
7. [FPGA Side: OpenNIC Packet Parser](#7-fpga-side-opennic-packet-parser)
8. [Building the Parser Bitstream](#8-building-the-parser-bitstream)
9. [Programming the FPGA and Bringing Up the Interface](#9-programming-the-fpga-and-bringing-up-the-interface)
10. [Reproducing the End-to-End Parser Demo](#10-reproducing-the-end-to-end-parser-demo)
11. [Reproducing the CPU Benchmark Suite](#11-reproducing-the-cpu-benchmark-suite)
12. [Canonical Results](#12-canonical-results)
13. [Engineering Notes and Bring-Up Debug Narrative](#13-engineering-notes-and-bring-up-debug-narrative)
14. [Known Limitations and Future Work](#14-known-limitations-and-future-work)
15. [References](#15-references)

---

## 1. Project Overview

### 1.1 Problem statement

In production HFT environments the critical path between an inbound market-data packet arriving on the wire and an outbound order leaving the wire is budgeted in hundreds of nanoseconds. Of that budget, software running on a general-purpose CPU typically spends:

- 40–200 ns parsing the inbound market-data feed (NASDAQ ITCH or equivalent)
- 30–80 ns servicing kernel-mediated network I/O
- 60–150 ns on memory-mapped I/O reads against external accelerators

Each of these is software-visible work that pays the full cost of a cache-traversing load or a non-bypassable instruction-fetch pipeline. The thesis question is whether displacing these stages into purpose-built hardware — a custom ISA extension on the processor side and a programmable FPGA parser on the network side — produces a measurably shorter critical path.

### 1.2 Two-stage architecture

The system is co-designed in two halves that can be reasoned about and validated independently:

```
       ┌─────────────────────────────────────────┐
       │           FPGA  (Xilinx U55C)           │
       │  ┌────────┐    ┌──────────┐   ┌──────┐  │       ┌──────────┐
Wire ──┼─▶│ 100 G  │───▶│ ITCH     │──▶│ BAR2 │──┼──────▶│  Host    │
       │  │ CMAC   │    │ parser   │   │ regs │  │ PCIe  │  (Linux) │
       │  └────────┘    └──────────┘   └──────┘  │       └──────────┘
       │      ▲                                  │            │
       │      │  (CMAC TX)                       │            │
       │      │                                  │            │
       │      └──────────────────────────────────┼────────────┘
       │                                         │  kernel-emitted UDP
       └─────────────────────────────────────────┘
```

```
                   ┌──────────────────────────────────────────────┐
                   │  Custom RV32IM OoO core (VCS simulation)     │
                   │                                              │
   parsed trade ──▶│  fetch_trade rd, imm    (custom-1)           │
                   │       │                                      │
                   │       ▼                                      │
                   │  decision logic (RV32I)                      │
                   │       │                                      │
                   │       ▼                                      │
                   │  pkt_w / pkt_s / pkt_st  (custom-2)          │──▶ AXI-Stream
                   │                                              │     order frame
                   └──────────────────────────────────────────────┘
```

The FPGA side is validated on real silicon (Xilinx U55C, PCIe-attached). The CPU side is validated via cycle-accurate simulation in Synopsys VCS.

### 1.3 Headline results

| Metric | Value | Where measured |
|---|---|---|
| `fetch_trade` single-shot speedup vs MMIO | **1.78×** | VCS sim (`itch_custom` vs `itch_mmio`) |
| Steady-state speedup vs MMIO | 1.12× | VCS sim (1000-iteration loop) |
| End-to-end tick-to-trade latency | **94 cycles** | VCS sim, `itch_tick_to_trade` |
| Equivalent wall-clock @ 322 MHz | ≈ 290 ns | derived |
| Equivalent wall-clock @ 200 MHz | ≈ 470 ns | derived |
| Peak measured TX throughput | **5.66 Gbps** | VCS sim, `itch_max_throughput` @ 322 MHz |
| Theoretical TX drain ceiling | 10.3 Gbps | derived from 16-beat drain limit |
| FPGA parser end-to-end | **all fields correct** | U55C silicon, see §10 |

---

## 2. Repository Structure

```
ie497/                                 ← top-level project repo
├── README.md                          ← brief landing description
├── REPORT.md                          ← this document
├── .gitmodules                        ← submodule pointers
│
├── open-nic-shell/                    ← FPGA parser (submodule)
│   ├── plugin/p2p/                    ← parser plugin (Box1 @ 322 MHz)
│   │   ├── p2p_322mhz.sv              ← AXI-Lite slave + register map
│   │   ├── packetparser_322mhz_simple.sv  ← parser FSM (tier 3)
│   │   └── box_322mhz/                ← box-level wiring
│   ├── plugin/cpu/                    ← CPU plugin slot (Box0 @ 250 MHz)
│   ├── src/cmac_subsystem/            ← Xilinx CMAC wrapper (modified)
│   │   └── cmac_subsystem_cmac_wrapper.sv  ← PCS loopback + pm_tick
│   └── script/                        ← build + host-side tools
│       ├── build.tcl                  ← Vivado build entry point
│       ├── program_fpga.sh            ← FPGA programming flow
│       ├── setup_device.sh            ← PCIe enumeration helper
│       ├── bar_read.py                ← privileged BAR2 read tool
│       ├── bar_write.py               ← privileged BAR2 write tool
│       ├── read_parser_regs.py        ← decode all 33 parser registers
│       ├── send_itch.py               ← MoldUDP64/ITCH UDP sender
│       └── send_raw_bytes.py          ← diagnostic UDP byte-pattern sender
│
└── riscv-cpu/                         ← Custom RISC-V CPU (submodule)
    ├── pkg/types.sv                   ← ISA + FU + RS typedefs
    ├── hdl/core/                      ← OoO core: decode, rename, dispatch, ROB, CPU top
    ├── hdl/execution/                 ← FUs and reservation stations
    │   ├── fetch_trade.sv             ← custom-1 RX FU + BRAM-backed FIFO
    │   ├── fetch_trade_rs.sv          ← custom-1 RS
    │   ├── pkt_tx.sv                  ← custom-2 TX FU + staging FIFO + FSM
    │   └── pkt_tx_rs.sv               ← custom-2 RS
    ├── hvl/common/                    ← testbench (sim-only)
    │   ├── fake_packet_parser.sv      ← behavioral RX driver
    │   ├── fake_packet_sink.sv        ← AXI-Stream TX sink
    │   └── top_tb.svh                 ← latency-instrumentation harness
    ├── testcode/sim_b/                ← benchmark C programs
    ├── sim/Makefile                   ← VCS build flow
    └── run.sh                         ← top-level sim invocation
```

The two subprojects are independent — the CPU sim does not depend on the FPGA build, and vice versa. They share an architectural model (the parser drives the same field layout the CPU side reads), but no code or build artifacts.

---

## 3. Hardware and Software Environment

### 3.1 Lab machines

| Hostname | Role | Has U55C? | Has Vivado? | Has VCS? | OS / Kernel |
|---|---|---|---|---|---|
| `hft03` | FPGA host, parser bring-up | **Yes** (BDF `0000:83:00.0`) | Yes | No | Ubuntu / Linux 5.15.0-177-generic |
| `hft06` | Vivado build machine | No | Yes | No | Ubuntu / Linux 5.15.x |
| EWS (UIUC Engineering Workstations) | CPU simulation | No | No | **Yes** (Synopsys VCS) | RHEL 8 / Linux 4.18 |

Builds can run on either `hft03` or `hft06`; both have Vivado. We typically run parser builds on `hft06` so `hft03` is free for programming and testing.

The CPU simulation does **not** synthesize on Vivado because the baseline RV32IM core uses Synopsys DesignWare IP (`DW02_mult`, `DW_div_seq`) which is ASIC-only. All cycle-accurate CPU numbers are measured in VCS on EWS.

### 3.2 Tool versions

| Tool | Where used | Version observed | Notes |
|---|---|---|---|
| Xilinx Vivado | `hft06` (and `hft03` for the secondary build) | 2022.1 or later (any version supporting au55c) | The OpenNIC build TCL is version-agnostic; we did not depend on any specific Vivado feature beyond the standard 100G CMAC v3.1 IP. |
| Synopsys VCS | EWS | as installed on EWS (2024.x) | invoked through the CPU repo's existing `sim/Makefile` |
| RISC-V GCC | EWS | `riscv64-unknown-elf-gcc` (whatever EWS provides) | targets `rv32i_zicsr` after the M-extension was deleted; before that, `rv32im` |
| `gcc` / `make` on the host | `hft03` | system default | for `bar_read.py` / `bar_write.py` (no native compile needed; they are Python) |
| Python | `hft03`, `hft06` | 3.8+ | `bar_read.py`, `bar_write.py`, `read_parser_regs.py`, `send_itch.py`, `send_raw_bytes.py` all run on Python 3 only |

### 3.3 OpenNIC dependencies

The OpenNIC framework requires:

- The Xilinx 100G Ethernet Subsystem IP (`cmac_usplus_0_au55c` configured via TCL — license required, available through the campus Xilinx license server)
- Xilinx QDMA IP
- Xilinx AXI Crossbar / Clock Converter IPs

All IPs are instantiated through the `.tcl` files committed in `open-nic-shell/src/`. No manual IP configuration is required for a fresh clone.

### 3.4 Host PCIe device identity (on `hft03`)

The Xilinx Alveo U55C accelerator on `hft03` is permanently enumerated at:

| Property | Value |
|---|---|
| PCI BDF | `0000:83:00.0` |
| Upstream bridge BDF | `0000:80:02.0` |
| Vendor:Device | Xilinx Corporation `903f` |
| PCI Class | Network controller |
| BAR2 resource | `/sys/bus/pci/devices/0000:83:00.0/resource2` (4 MB) |
| Linux netdev (when driver bound) | `ens2` |

The BDF values are stable across reboots on `hft03` and are referenced directly in `bar_read.py`, `bar_write.py`, and `program_fpga.sh`. If the project is moved to a different host, only the BDF constant inside the two BAR helpers (`BDF = "0000:83:00.0"`) needs updating.

---

## 4. Required Privileges and Sudoers Configuration

The OpenNIC programming flow and BAR-region access both require root for specific operations. To allow non-root team members to perform reproducible programming and register reads without password prompts, the lab administrator (the course instructor in our case) installs a scoped sudoers entry.

### 4.1 The sudoers entry installed on `hft03`

File: `/etc/sudoers.d/sp26-ie497-dl-grp03`

```
%sp26-ie497-dl-grp03 ALL=(ALL) NOPASSWD: /home/suvids2/open-nic-shell/script/setup_device.sh *
%sp26-ie497-dl-grp03 ALL=(ALL) NOPASSWD: /home/suvids2/open-nic-shell/script/program_fpga.sh *
%sp26-ie497-dl-grp03 ALL=(ALL) NOPASSWD: /usr/local/bin/bar_read *
%sp26-ie497-dl-grp03 ALL=(ALL) NOPASSWD: /usr/local/bin/bar_write *
```

### 4.2 What each grant covers

- **`setup_device.sh *` and `program_fpga.sh *`** — These two scripts internally call `setpci`, `tee /sys/bus/pci/devices/.../remove`, `tee /sys/bus/pci/devices/.../rescan`, and `rmmod` / `insmod` on the onic kernel driver. By granting NOPASSWD on the *scripts*, the host operator avoids granting wildcard NOPASSWD on the underlying system commands (which would create a much broader privilege footprint). The scripts themselves are root-owned with mode 0755, so unprivileged users cannot modify them to escape the intended scope.

- **`/usr/local/bin/bar_read *` and `/usr/local/bin/bar_write *`** — These are Python helpers (described in §7.5) that mmap-read or mmap-write BAR2 of a specific BDF, with bounds checking. They are root-owned 0755 binaries installed via:

  ```bash
  sudo install -m 0755 -o root -g root \
      open-nic-shell/script/bar_read.py \
      /usr/local/bin/bar_read

  sudo install -m 0755 -o root -g root \
      open-nic-shell/script/bar_write.py \
      /usr/local/bin/bar_write
  ```

  The scoped wildcard `*` after the path lets group members pass arbitrary register offsets and (for `bar_write`) values, while still preventing them from invoking any other binary. The internal bounds check inside `bar_read.py` / `bar_write.py` enforces that offset + 4 ≤ BAR size and refuses anything beyond.

### 4.3 Membership requirement

The user account performing FPGA bring-up must be a member of the Unix group `sp26-ie497-dl-grp03`. Verify with:

```bash
id | tr ',' '\n' | grep sp26-ie497-dl-grp03
```

If the group does not appear, log out and back in (the group may have been added after the current session started) or request membership from the course instructor.

### 4.4 No CPU-side privileges required

The cycle-accurate RISC-V simulation runs entirely as the user on EWS. No sudo is needed for anything in the `riscv-cpu/` subtree.

---

## 5. Cloning and Initial Setup

The repository is hosted on UIUC's GitLab. Clone with submodules:

```bash
# Choose any clone location — the project does not assume a specific path.
# All commands below are written relative to the clone root.

git clone --recursive <gitlab-url-or-ssh-spec> ie497
cd ie497

# If you cloned without --recursive, fetch the submodules now:
git submodule update --init --recursive
```

This brings down both subprojects:

- `open-nic-shell/` — fork of Xilinx OpenNIC with the parser plugin and CMAC-wrapper modifications
- `riscv-cpu/` — the custom RV32IM out-of-order core with the four custom instructions

The remainder of this document refers to the clone root as `${PROJECT_ROOT}`. Every command shown is relative to it; no absolute paths to anyone's home directory are baked in.

### 5.1 Adding the BAR helpers to the system path on `hft03`

Required only once per host, after `git pull`. From the clone root:

```bash
sudo install -m 0755 -o root -g root open-nic-shell/script/bar_read.py  /usr/local/bin/bar_read
sudo install -m 0755 -o root -g root open-nic-shell/script/bar_write.py /usr/local/bin/bar_write
```

(These commands need root once for installation, but afterwards the scoped sudoers rule in §4 allows the group to invoke the installed binaries without a password.)

### 5.2 Host network configuration on `hft03`

After the FPGA is programmed (§9), the OpenNIC interface comes up as `ens2`. We use a static unrouted subnet, with a manual ARP entry so the kernel will transmit UDP without ARP resolution depending on the (deliberately absent) network partner:

```bash
sudo ip link set ens2 up
sudo ip addr add 10.0.0.3/24 dev ens2
sudo arp -i ens2 -s 10.0.0.99 02:00:00:00:00:99
```

`10.0.0.99` is the deliberately unassigned destination IP we send UDP test packets to. The static ARP entry pre-resolves it to a synthetic MAC so the Linux kernel will transmit the UDP frame without waiting for an ARP reply that will never come (the CMAC's PCS internal loopback returns the frame to ourselves rather than to any partner).

---

## 6. RISC-V CPU Side: Custom Instructions in Simulation

This section describes the simulation-only CPU half of the project. Everything in this section lives under `${PROJECT_ROOT}/riscv-cpu/` and is exercised by running the existing VCS-based test flow on EWS.

### 6.1 Baseline core

- Non-superscalar out-of-order RV32IM core with:
  - 32 architectural / 64 physical registers
  - 32-entry ROB
  - Distributed reservation stations (ALU=16, BR=8, MUL=8, DIV=4, MEM=16)
  - Three common data buses: `cdb_alu_br`, `cdb_mul_div`, `cdb_mem`
- Inherited from the team's IE421 final project (graded A); modified to add the custom instructions described below.

### 6.2 Custom-1: `fetch_trade` (RX side)

**Encoding.** I-type, opcode `0x0B` (RV custom-1 space). The 3-bit immediate selects a *slot* of the current head packet in the parser's RX FIFO. There is no source operand.

**Semantics.**

```text
fetch_trade rd, imm[2:0]   →  rd ← parsed_packet[head].slot[imm]
```

**Slot layout** (per parsed packet, 8 slots × 32 bits = 256 bytes per packet):

| Slot | Meaning |
|---|---|
| 0 | Message type (`'A'`, `'F'`, etc., in low byte) |
| 1 | Stock locate |
| 2 | Shares (32-bit) |
| 3 | Price (32-bit) |
| 4 | **Empty flag** (read-only; returns 1 if FIFO empty) |
| 5 | **Pop trigger** (read advances `tail_ptr`) |
| 6 | Sequence number |
| 7 | Reserved |

**Hardware.** Backed by a single Xilinx `xpm_memory_sdpram` BRAM18 primitive. 8 packets × 8 slots × 32 bits, dual-ported (parser drives Port A, CPU reads Port B). A 4-bit `head_ptr` and `tail_ptr` implement an 8-deep FIFO with empty/full detection. Dispatch-to-CDB latency is 2 cycles. A minimal 4-entry RS holds in-flight `fetch_trade` instructions; no operand wakeup is needed since the instruction has no source register.

**Static benchmark compatibility.** `head_ptr` resets to 1 and the BRAM's `MEMORY_INIT_PARAM` populates packet 0 with constants. This lets the legacy single-shot benchmarks (the three-path baseline) run without the parser stream being active.

### 6.3 Custom-2: `pkt_w` / `pkt_s` / `pkt_st` (TX side)

**Encoding.** All three share opcode `0x2B` (RV custom-2 space), discriminated by `funct3`. Encodings are defined in `riscv-cpu/pkg/types.sv`.

| Mnemonic | Source | Destination | Semantics |
|---|---|---|---|
| `pkt_w rs1, imm[3:0]` | `rs1` | none | Writes the 4 bytes of `rs1` into the current staging slot of the TX BRAM, at 32-bit word offset `imm`. |
| `pkt_s rs1` | `rs1` | none | Commits the current staging slot for emission; `rs1` carries the byte length to send (1–64). Advances `staging_ptr`. |
| `pkt_st rd, imm[2:0]` | none | `rd` | Reads one of four status fields (empty / full / busy / pending-count) from the TX subsystem and returns it in `rd`. |

**Hardware.** Backed by a single BRAM holding 8 staging slots × 16 words × 32 bits = 512 bytes. Port A is the CPU write side; Port B feeds an FSM that drains a slot out to an AXI-Stream master interface (`m_axis_pkt_tx_*`) at one 32-bit beat per cycle. The producer (CPU) and consumer (FSM) operate on different slots concurrently, which lets the firmware stage packet *N+1* while hardware is still emitting packet *N*. This decoupling is the architectural advantage of the multi-buffer design over a single-buffer alternative.

**Status fields** (read via `pkt_st`):

| imm | Field |
|---|---|
| 0 | `tx_empty` — staging FIFO empty AND FSM IDLE (all sends drained) |
| 1 | `tx_full` — next `pkt_s` would stall the RS |
| 2 | `tx_busy` — FSM is in SEND state |
| 3 | `tx_pending` — count of staged-but-not-drained packets (0–8) |

These let firmware do back-pressure-aware sending and end-of-batch synchronization without spinning on `pkt_s` itself.

### 6.4 Three-path comparison benchmark

The most direct measurement of the custom ISA value is the single-shot, three-implementation comparison of an identical ITCH-decision workload:

| Path | Mechanism | Cycles |
|---|---|---|
| Software ITCH parse | parse raw bytes, branch on `mtype`/price/shares | **234** |
| MMIO load | `lw` from pre-parsed BRAM exposed at a memory-mapped address | **105** |
| Custom `fetch_trade` | single instruction returning the field directly | **59** |

The `fetch_trade` path is **1.78× faster than MMIO and 4.0× faster than software parsing** on a single decision. Source: `riscv-cpu/testcode/sim_b/itch_{software,mmio,custom}.c`.

### 6.5 Tick-to-trade waterfall

`riscv-cpu/testcode/sim_b/itch_tick_to_trade.c` exercises the entire pipeline end-to-end inside the simulator:

1. A behavioral parser (`riscv-cpu/hvl/common/fake_packet_parser.sv`) writes parsed-trade structures into the `fetch_trade` BRAM at a configurable inter-arrival rate.
2. Firmware polls the FIFO empty flag, reads price/shares via `fetch_trade`, applies the decision predicate `mtype == 'A' && price > threshold && shares >= min`.
3. On accept, firmware builds a valid Ethernet/IPv4/UDP/OUCH order frame in the TX BRAM via 16 × `pkt_w` and fires it with `pkt_s 64`.
4. A behavioral sink (`riscv-cpu/hvl/common/fake_packet_sink.sv`) captures the emitted frame for byte-level validation.

Per-segment cycle accounting on steady-state accepts (excluding the cold-start packet 0):

| Segment | Cycles |
|---|---|
| Parser commit → `fetch_trade` writeback | 2.8 |
| Decision + build frame (16× `pkt_w` + `pkt_s` + branches) | 60.5 |
| `pkt_s` dispatch → FSM IDLE→SEND | 4.0 |
| FSM setup → first AXI-Stream beat | ≈ 10 |
| First beat → `tlast` (16-beat drain at 1 word/cycle) | 16.0 |
| **Total tick-to-trade** | **≈ 94** |

At 322 MHz this is ≈ 290 ns. At 200 MHz, ≈ 470 ns.

### 6.6 Packet-length sweep

`itch_tick_to_trade_sweep.c` repeats the closed-loop test for `pkt_s` lengths of 16, 32, 48, and 64 bytes. The TX drain segment scales linearly (one beat per 4 bytes); the issue and fill segments stay flat. This validates that the TX primitive is drain-limited rather than dispatch-limited for sub-64-byte frames.

### 6.7 Two-protocol demonstration

`itch_two_protocol.c` emits one ARP-shaped frame followed by 49 OUCH-shaped frames from the *same* firmware using the *same* `pkt_w` / `pkt_s` calls. A Python decoder (`riscv-cpu/script/decode_two_protocol.py`) reads the captured TX log and dispatches by ethertype:

```
counts:   ARP = 1   OUCH = 49   UNKNOWN = 0
all frames structurally valid: True
```

This is the concrete proof that the TX primitive is protocol-agnostic — the hardware doesn't know or care which protocol the firmware constructs.

### 6.8 Maximum throughput benchmark

`itch_max_throughput.c` uses `pkt_st` to drive the queue to saturation: it polls `pkt_st(tx_full)` to keep the staging FIFO full and `pkt_st(tx_empty)` for end-of-batch synchronization. Result: **29.14 cycles per 64-byte packet** sustained over 100 packets, against the theoretical drain limit of 16 cycles/packet. The 13.14-cycle gap is FU-bound — primarily the 16 sequential `pkt_w` instructions through a depth-4 RS, plus the misprediction cost of the `pkt_st`-polled inner loop.

Translated to bandwidth:

| Clock | Measured | Theoretical drain ceiling |
|---|---|---|
| 322 MHz | **5.66 Gbps** | 10.30 Gbps |
| 200 MHz | 3.51 Gbps | 6.40 Gbps |

### 6.9 RX FIFO streaming latency

`itch_stream.c` runs 100 streamed packets through the behavioral parser at parser interval = 512 cycles. Latency from `parser_commit` to `fetch_trade` writeback:

| Statistic | Cycles |
|---|---|
| min | 11 |
| p50 | 31 |
| p99 | 36 |
| max (steady-state, excl. cold start) | 36 |
| max (incl. row 0 cold start) | 373 |
| drops at parser interval = 512 | 0 |

Saturation occurs at parser interval = 16 (215 parser writes / 100 commits). At parser interval ≥ 256, zero drops are observed.

---

## 7. FPGA Side: OpenNIC Packet Parser

This section describes the hardware half of the project — a Verilog packet-parser plugin synthesized into the OpenNIC framework and running on the U55C accelerator card in `hft03`.

### 7.1 OpenNIC architecture, abridged

OpenNIC ([Xilinx/open-nic](https://github.com/Xilinx/open-nic)) is an open-source FPGA framework providing:

- 100 Gigabit Ethernet via the Xilinx CMAC subsystem
- PCIe DMA via the Xilinx QDMA subsystem
- Two user-logic regions (called "boxes") at separate clock frequencies (250 MHz and 322 MHz) into which custom plugins can be dropped
- An AXI-Lite address map exposed to the host via PCIe BAR2

System-level BAR2 address map (from `src/system_config/system_config_address_map.sv`):

| Range | Module |
|---|---|
| `0x00000 – 0x00FFF` | System configuration |
| `0x01000 – 0x05FFF` | QDMA subsystem #0 |
| `0x08000 – 0x0AFFF` | CMAC subsystem #0 |
| `0x0B000 – 0x0BFFF` | Packet adapter #0 |
| `0x10000 – 0x11FFF` | Sysmon block |
| `0x100000 – 0x1FFFFF` | **Box0 @ 250 MHz** |
| **`0x200000 – 0x2FFFFF`** | **Box1 @ 322 MHz** — our parser lives here |
| `0x300000 – 0x33FFFF` | Card management system |

The parser plugin is placed at the base of Box1 (BAR2 offset `0x200000`).

### 7.2 Parser plugin

Top-level file: `open-nic-shell/plugin/p2p/p2p_322mhz.sv`. The plugin exposes:

- An AXI-Lite slave for the host to read parser state (28 registers — see §7.4)
- An AXI-Stream receive snoop on the CMAC RX bus (`s_axis_cmac_rx_*`)
- Pass-through AXI-Stream of all four data paths (CMAC↔QDMA in both directions) so the parser is non-intrusive on regular packet flow

Inner parser FSM: `open-nic-shell/plugin/p2p/packetparser_322mhz_simple.sv`. The simple parser handles up to 2 ITCH messages per packet (Tier 3 layout), with cross-beat message-2 completion for layouts where msg2 spans the AXI-Stream beat boundary. It supports three ITCH message types:

| Byte | Mnemonic | ITCH Spec |
|---|---|---|
| `0x41` | `'A'` Add Order | section 4.3.1 |
| `0x69` | `'i'` (Tier 3) Add Order with MPID Attribution | section 4.3.2 |
| `0x68` | `'h'` Stock Trading Action | section 4.3.6 |

Any other message type byte falls into a `default` case that increments `COUNT_UNKNOWN`.

### 7.3 Plugin data path

```
CMAC RX (322 MHz, 512 b AXI-Stream) ──┬──▶ s_axis_cmac_rx_* (parser snoops)
                                       │
                                       └──▶ m_axis_adap_rx_* (forwarded to QDMA)

QDMA C2H → adap_rx (250 MHz)  ──▶ packet_adapter ──▶ host kernel

QDMA H2C ← adap_tx (250 MHz) ◀── packet_adapter ◀── host kernel
                                       │
                                       └──▶ m_axis_cmac_tx_* (322 MHz)
```

The parser is purely a snoop on the CMAC RX path; it does not gate or modify the AXI-Stream that flows back up to the QDMA. The host's normal networking continues to function in parallel with parsing.

### 7.4 AXI-Lite register map

Base address: BAR2 `0x200000`. All registers are 32 bits wide.

| Offset | Name | Type | Description |
|---|---|---|---|
| `0x00` | `REG_MAGIC` | RO const | `0x49544348` ("ITCH" in ASCII) — sanity check |
| `0x04` | `REG_VERSION` | RO const | Plugin version (currently `0x00000001`) |
| `0x08` | `REG_PACKET_COUNT` | RO | Total Ethernet frames seen on CMAC RX |
| `0x0C` | `REG_PARSED_MSG_COUNT` | RO | Total ITCH messages successfully parsed |
| `0x10` | `REG_LAST_MSG_TYPE` | RO | 1-byte ITCH message type from most recent parse |
| `0x14` | `REG_LAST_SRC_IP` | RO | IPv4 source address of most recent packet |
| `0x18` | `REG_LAST_DST_IP` | RO | IPv4 destination address |
| `0x1C` | `REG_LAST_PORTS` | RO | `{src_port[31:16], dst_port[15:0]}` |
| `0x20` | `REG_LAST_SEQ_LOW` | RO | MoldUDP64 sequence number, low 32 bits |
| `0x24` | `REG_LAST_SEQ_HIGH` | RO | MoldUDP64 sequence number, high 32 bits |
| `0x28` | `REG_LAST_MSG_NUM` | RO | MoldUDP64 message count for last packet |
| `0x2C` | `REG_LAST_STOCK_LOCATE` | RO | ITCH stock locate field |
| `0x30` | `REG_LAST_TIMESTAMP_LOW` | RO | ITCH 6-byte timestamp, low 32 bits |
| `0x34` | `REG_LAST_TIMESTAMP_HIGH` | RO | ITCH timestamp, high 16 bits |
| `0x38` | `REG_LAST_REF_NUM_LOW` | RO | ITCH order reference number, low 32 bits |
| `0x3C` | `REG_LAST_REF_NUM_HIGH` | RO | ITCH ref num, high 32 bits |
| `0x40` | `REG_LAST_BUY_SELL` | RO | ITCH buy/sell indicator (`'B'` or `'S'`) |
| `0x44` | `REG_LAST_SHARE_AMT` | RO | ITCH share amount |
| `0x48` | `REG_LAST_STOCK_SYM_LOW` | RO | ITCH 8-byte stock symbol, low 32 bits |
| `0x4C` | `REG_LAST_STOCK_SYM_HIGH` | RO | ITCH stock symbol, high 32 bits |
| `0x50` | `REG_LAST_PRICE` | RO | ITCH price |
| `0x54` | `REG_PARSER_STATUS` | RO | 4-bit status: `{snapshot_toggle, packet_toggle, |parsed_msg_count, |packet_count}` |
| `0x58` | `REG_CLEAR_COUNTS` | RW | Reserved (always reads 0) |
| `0x5C` | `REG_COUNT_ADD_ORDER` | RO | Total `0x41` ('A') messages parsed |
| `0x60` | `REG_COUNT_ORDER_EXECUTED` | RO | Total `0x69` ('i') messages parsed |
| `0x64` | `REG_COUNT_STOCK_ACTION` | RO | Total `0x68` ('h') messages parsed |
| `0x68` | `REG_COUNT_UNKNOWN` | RO | Total messages with unrecognized type byte |
| `0x6C` | `REG_DBG_BEAT_COUNT` | RO | Total AXI-Stream beats observed (diagnostic) |
| `0x70` | `REG_DBG_BEAT0_COUNT` | RO | Total entries into parser Beat-0 branch (diagnostic) |
| `0x74` | `REG_DBG_BEAT1_COUNT` | RO | Total entries into parser Beat-1 branch (diagnostic) |
| `0x78` | `REG_DBG_LAST_MSG_TYPE` | RO | Byte the parser actually read from `tdata[511:504]` of most recent Beat-1 (diagnostic) |
| `0x7C` | `REG_DBG_LAST_TKEEP_LOW` | RO | `tkeep[31:0]` on most recent `tlast` (diagnostic) |
| `0x80` | `REG_DBG_LAST_TKEEP_HIGH` | RO | `tkeep[63:32]` on most recent `tlast` (diagnostic) |

The seven diagnostic registers (offsets `0x6C` onward) were added during bring-up to isolate the byte-ordering issue described in §13. They remain in the final design as runtime instrumentation.

### 7.5 Host-side tools

All five tools live under `open-nic-shell/script/`:

**`bar_read.py`** — privileged 32-bit word read from BAR2.

```bash
sudo bar_read 0x200000          # → 0x49544348  ("ITCH" magic)
sudo bar_read 0x20000C          # → REG_PARSED_MSG_COUNT
```

The binary BDF and BAR size are hardcoded for `hft03`'s U55C; portability is a single-line edit.

**`bar_write.py`** — privileged 32-bit word write to BAR2.

```bash
sudo bar_write 0x8090 0x00002222    # write GT_LOOPBACK_REG_0 (CMAC IP)
```

Added during bring-up; useful for poking CMAC IP registers without rebuilding.

**`read_parser_regs.py`** — high-level wrapper that calls `bar_read` for every register in the map and decodes each value (ASCII for MAGIC and stock symbol, dotted-quad for IPs, ASCII for buy/sell, etc.).

```bash
python3 open-nic-shell/script/read_parser_regs.py
```

The script is unprivileged; only its inner `bar_read` invocations require sudo (covered by the NOPASSWD rule in §4).

**`send_itch.py`** — pure-Python UDP sender that builds MoldUDP64-wrapped ITCH Add Order messages.

```bash
python3 open-nic-shell/script/send_itch.py \
    --src-ip 10.0.0.3 --dst-ip 10.0.0.99 \
    --count 5 --interval 0.2
```

Options:

- `--src-ip` / `--dst-ip` / `--dst-port` — UDP destination (default port 9000)
- `--count` — number of packets (0 = forever)
- `--interval` — seconds between packets
- `--pad-bytes` — append N zero bytes to the UDP payload (used for diagnostic multi-beat sends; see §13)

**`send_raw_bytes.py`** — diagnostic UDP sender that emits a payload of N copies of a single byte value. Used during bring-up to probe what bytes the parser actually reads at the supposed `msg_type` position regardless of ITCH structure.

```bash
sudo python3 open-nic-shell/script/send_raw_bytes.py \
    --src-ip 10.0.0.3 --dst-ip 10.0.0.99 \
    --count 5 --interval 0.2 --byte 0x41 --length 1000
```

---

## 8. Building the Parser Bitstream

The Vivado build is parameterized through `open-nic-shell/script/build.tcl`. A typical invocation:

```bash
# From either hft06 or hft03 — both have Vivado.
# Use tmux so the build survives SSH disconnects.

tmux new -s build_parser

cd open-nic-shell/script

vivado -mode batch -source ./build.tcl -tclargs \
    -board au55c \
    -tag <your-build-tag> \
    -user_plugin ../plugin/p2p \
    -impl 1 \
    -post_impl 1 \
    -overwrite 1 \
    -jobs 8 \
    2>&1 | tee ../build_<your-tag>.log
```

`-tag` is a free-form label that becomes the build directory name (e.g., `au55c_parser_v4_byteswap`).

`-user_plugin` selects which plugin tree to use. For the parser, this is `plugin/p2p` (the OpenNIC default). For builds that include both the parser and a CPU plugin stub in Box0, see §8.2.

Detach the tmux session with **`Ctrl-B` then `D`**. Re-attach with `tmux attach -t build_parser`. The build takes **3–5 hours wall-clock** on `hft06`.

### 8.1 Where the bitstream lands

```
open-nic-shell/build/au55c_<tag>/open_nic_shell/open_nic_shell.runs/impl_1/open_nic_shell.bit
```

This is the file you point `program_fpga.sh` at in §9.

### 8.2 Optional: include a Box0 plugin in the same bitstream

`build.tcl` supports a per-box plugin fallback. If you pass `-user_plugin <path>` and that path contains a `box_322mhz/` subdirectory the build uses it for Box1; otherwise it falls back to `plugin/p2p/box_322mhz/` (the parser). The same logic applies to `box_250mhz/`. This makes it possible to produce a single bitstream containing both the parser (Box1) and a custom CPU stub (Box0):

```
plugin/cpu/
├── cpu_stub.sv                     # AXI-Lite slave returning "RISC" magic
├── box_250mhz/                     # contains the stub plugin
│   └── ...
└── build_box_250mhz.tcl
# (no box_322mhz/ subdir, so Box1 falls back to plugin/p2p/box_322mhz/)
```

Invoke with `-user_plugin ../plugin/cpu`. Box0 gets `cpu_stub`; Box1 keeps the parser unchanged.

### 8.3 Timing closure

The parser closes timing comfortably:

```
WNS (worst negative slack):     +7.386 ns
WHS (worst hold slack):         +0.025 ns
TNS (total negative slack):     0 ns
```

The 322 MHz CMAC domain and the 250 MHz Box0 domain have separate clock-converter IPs on AXI-Lite paths; there are no cross-domain timing exceptions required.

---

## 9. Programming the FPGA and Bringing Up the Interface

This is the full sequence to go from a freshly-built bitstream to a verified end-to-end parser demo on `hft03`.

### 9.1 Pre-flight check

```bash
# Confirm the device exists in PCIe (it may need a rescan if a prior session removed it):
ls /sys/bus/pci/devices/0000:83:00.0/ 2>/dev/null

# If not present, rescan the bridge:
echo 1 | sudo tee /sys/bus/pci/devices/0000:80:02.0/rescan
ls /sys/bus/pci/devices/0000:83:00.0/
```

You should see a populated directory containing at least `resource2`, `vendor`, `device`.

### 9.2 Unload the existing onic driver (if loaded)

```bash
lsmod | grep onic
sudo rmmod onic     # use rmmod (not modprobe -r): the .ko lives outside /lib/modules
```

### 9.3 Run `program_fpga.sh`

```bash
cd open-nic-shell/script
export EXTENDED_DEVICE_BDF1=0000:83:00.0
./program_fpga.sh ../build/au55c_<tag>/open_nic_shell/open_nic_shell.runs/impl_1/open_nic_shell.bit au55c
```

The script:

1. Disables SERR and ERR_FATAL on the bridge (`setpci -s 0000:80:02.0 COMMAND=0000:0100`, `CAP_EXP+8.w=0000:0004`)
2. Opens the Vivado hardware manager, programs the bitstream
3. After you press **`c`**, removes the PCIe device, rescans the bridge, re-enables memory space (`setpci -s 0000:83:00.0 COMMAND=0x02`)

### 9.4 Load the onic driver

```bash
# Locate the .ko (it's outside /lib/modules so modprobe won't find it):
sudo find / -name onic.ko 2>/dev/null | head -1

# Load it (substitute the path you just found):
sudo insmod <path-to-onic.ko>

# Confirm:
lsmod | grep onic
ip -br link | grep ens2
```

### 9.5 Configure the network interface

```bash
sudo ip link set ens2 up
sudo ip addr add 10.0.0.3/24 dev ens2
sudo arp -i ens2 -s 10.0.0.99 02:00:00:00:00:99

ip -br addr show ens2              # expect: ens2 UP 10.0.0.3/24
ethtool ens2 | grep -E "Link|Speed" # expect: Link detected: yes  Speed: 100000Mb/s
```

`Link detected: yes` without any cable plugged in is the signature of working PCS internal loopback inside the CMAC. If it shows `no`, the loopback hardcoding in `src/cmac_subsystem/cmac_subsystem_cmac_wrapper.sv` line 305 has been reverted to `3'b000`; verify the source tree before re-running.

### 9.6 Sanity-check the parser is reachable

```bash
sudo bar_read 0x200000      # expect: 0x49544348  ("ITCH")
sudo bar_read 0x200004      # expect: 0x00000001  (version)
```

If `0x200000` returns `0x00000000`, the parser is at the wrong BAR offset (an earlier OpenNIC layout placed it at `0x10000` — this is fixed in our build but the symptom is identical if the wrong bitstream is loaded).

---

## 10. Reproducing the End-to-End Parser Demo

This is the canonical "everything works" demo. Run the full sequence from a single shell on `hft03` after §9 has been completed.

### 10.1 Capture a baseline

```bash
sudo arp -i ens2 -s 10.0.0.99 02:00:00:00:00:99   # idempotent
python3 open-nic-shell/script/read_parser_regs.py | tee /tmp/parser_baseline.txt
```

You should see `REG_MAGIC = 0x49544348 ("ITCH")` and `REG_VERSION = 0x00000001`. All `REG_LAST_*` fields will be zero on a fresh-programmed FPGA.

### 10.2 Send 5 ITCH packets

```bash
python3 open-nic-shell/script/send_itch.py \
    --src-ip 10.0.0.3 --dst-ip 10.0.0.99 \
    --count 5 --interval 0.2
```

Expected output: 5 `sent seq=N` lines.

### 10.3 Re-read and diff

```bash
python3 open-nic-shell/script/read_parser_regs.py | tee /tmp/parser_after.txt
diff /tmp/parser_baseline.txt /tmp/parser_after.txt
```

### 10.4 Expected diff

```
REG_PACKET_COUNT           +5     (parser saw 5 frames)
REG_PARSED_MSG_COUNT       +5     (parser successfully parsed 5 messages)
REG_LAST_MSG_TYPE          'A'    (0x41 = Add Order)
REG_LAST_BUY_SELL          'B'    (0x42 = buy)
REG_LAST_SRC_IP            10.0.0.3
REG_LAST_DST_IP            10.0.0.99
REG_LAST_PORTS             src=<ephemeral>  dst=9000
REG_LAST_SEQ_LOW           5                       (sequence # of 5th packet)
REG_LAST_MSG_NUM           1                       (1 message per MoldUDP64 packet)
REG_LAST_STOCK_LOCATE      0x1234                  (literal from send_itch.py)
REG_LAST_TIMESTAMP_LOW     0x2305                  (0x2300 + 5)
REG_LAST_REF_NUM_HIGH      0x0123ABCD              (literal upper 32 bits)
REG_LAST_REF_NUM_LOW       0x000186A5              (0x000186A0 + 5)
REG_LAST_SHARE_AMT         1004                    (1000 + 4 from packet 5)
REG_LAST_STOCK_SYM_HIGH    "AAPL"
REG_LAST_STOCK_SYM_LOW     "    "                  (4-space padding)
REG_LAST_PRICE             9989684                 (9989680 + 4)
REG_COUNT_ADD_ORDER        +5
```

Every parsed field exactly matches what `send_itch.py` placed in the outgoing packets. This is the FPGA half of the project verified end-to-end on real silicon.

### 10.5 Capturing the on-wire packet for the report

To produce a hex dump of the packets as they appear on `ens2`, run alongside the send:

```bash
# Terminal A:
sudo tcpdump -i ens2 -nn -e -X -c 5 udp port 9000 | tee /tmp/parser_wire.txt

# Terminal B (start after tcpdump is running):
python3 open-nic-shell/script/send_itch.py \
    --src-ip 10.0.0.3 --dst-ip 10.0.0.99 \
    --count 5 --interval 0.2
```

The captured 100-byte frames (14 Ethernet + 20 IPv4 + 8 UDP + 58 UDP payload) are the input the parser decodes.

---

## 11. Reproducing the CPU Benchmark Suite

All CPU simulations run on EWS via Synopsys VCS. There are no host-side configuration steps and no privileges required.

### 11.1 Environment setup

```bash
# On EWS:
cd riscv-cpu
source setup_env.sh    # loads VCS and the RISC-V toolchain
```

### 11.2 Single-benchmark run

```bash
make -C sim EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" run_vcs_top_tb \
    PROG=../testcode/sim_b/itch_custom.c
```

The `+define+ECE411_NO_SPIKE_DPI` flag disables the Spike ISA-simulator co-simulation, which Spike does not support for the custom opcodes. All custom-instruction benchmarks must be run with this flag.

Expected for `itch_custom.c`:

```
Segment Time:               109150 ps
Segment IPC:                0.237288
→ 109150 / 1850 = 59 cycles
```

### 11.3 Full regression set

| Benchmark | Expected | What it measures |
|---|---|---|
| `itch_software.c` | 234 cycles | Baseline software ITCH parsing |
| `itch_mmio.c` | 105 cycles | MMIO `lw` from pre-parsed BRAM |
| `itch_custom.c` | 59 cycles, IPC 0.237288 | `fetch_trade` single-shot |
| `itch_stream.c` | latency.csv byte-identical to `latency_interval_512.csv` | RX FIFO under streaming load |
| `itch_send_packet.c` | 64-byte capture clean, no spurious emits | TX primitive Phase 1 |
| `itch_send_overlap.c` | writes=128, emits=128, overlap=16 | TX primitive Phase 2 (multi-buffer) |
| `itch_tick_to_trade.c` | accepted=50, latency p50=79 | End-to-end closed loop |
| `itch_tick_to_trade_sweep.c` | drain scales linearly with length | Length sweep |
| `itch_two_protocol.c` | ARP=1, OUCH=49, UNKNOWN=0 | Protocol-agnosticism |
| `itch_max_throughput.c` | 29.14 cycles/packet | TX-side throughput ceiling |

### 11.4 Streaming-latency reproduction

```bash
make -C sim EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" run_vcs_top_tb \
    PROG=../testcode/sim_b/itch_stream.c \
    TIMEOUT=20000000 \
    EXTRA_RUN_ARGS="+PARSER_ENABLE_ECE411=1 +PARSER_INTERVAL_ECE411=512"
```

The output `latency.csv` is byte-identical to the saved baseline at `testcode/sim_b/latency_interval_512.csv`.

---

## 12. Canonical Results

This section is the single source of truth that the abstract and the writeup body cite. If a number appears anywhere else in this report and disagrees with this table, this table wins.

### 12.1 RISC-V CPU side (VCS, EWS)

| Benchmark | Metric | Value |
|---|---|---|
| `itch_software` | cycles | 234 |
| `itch_mmio` | cycles | 105 |
| `itch_custom` | cycles | **59** |
| `itch_custom` | IPC | 0.237288 |
| `fetch_trade` vs MMIO (single-shot) | speedup | **1.78×** |
| `fetch_trade` vs MMIO (steady-state, 1000-iter) | speedup | 1.12× |
| `itch_stream` (parser interval = 512) | p50 RX latency | 31 cycles |
| `itch_stream` (parser interval = 512) | p99 RX latency | 36 cycles |
| `itch_stream` (parser interval = 512) | drops | 0 |
| `itch_tick_to_trade` | accepted out of 100 | 50 |
| `itch_tick_to_trade` | steady-state p50 | 79 cycles |
| Full tick-to-trade (parser commit → tlast) | steady-state | **94 cycles** |
| Wall-clock @ 322 MHz | derived | ≈ 290 ns |
| `itch_send_overlap` (Phase 2 multi-buffer) | overlap cycles | 16 |
| `itch_max_throughput` | cycles per 64 B packet | 29.14 |
| `itch_max_throughput` | TX bandwidth @ 322 MHz | **5.66 Gbps** |
| `itch_max_throughput` | TX bandwidth @ 200 MHz | 3.51 Gbps |
| TX theoretical drain ceiling @ 322 MHz | derived | 10.30 Gbps |
| `itch_two_protocol` | ARP frames | 1 |
| `itch_two_protocol` | OUCH frames | 49 |
| `itch_two_protocol` | unknown frames | 0 |

### 12.2 FPGA parser side (U55C silicon, `hft03`)

| Quantity | Value |
|---|---|
| Build target | Xilinx Alveo U55C, OpenNIC framework |
| Bitstream WNS | + 7.386 ns |
| Bitstream WHS | + 0.025 ns |
| CMAC clock | 322 MHz |
| Loopback mode used for bring-up | PCS internal (`gt_loopback_in = 3'b001`) |
| AXI-Lite register block | 28 registers + 5 diagnostic = 33 total, BAR2 `0x200000–0x2000FF` |
| `REG_MAGIC` value | `0x49544348` ("ITCH") |
| End-to-end demo (5 × ITCH Add Order) | every field decoded exactly matches sender |

### 12.3 Verified field decode (from the §10 demo)

| Sender wrote | Parser decoded |
|---|---|
| `msg_type = 'A'` (0x41) | `REG_LAST_MSG_TYPE = 0x41` ✓ |
| `buy_sell = 'B'` (0x42) | `REG_LAST_BUY_SELL = 0x42` ✓ |
| src IP `10.0.0.3` | `REG_LAST_SRC_IP = 0x0A000003` ✓ |
| dst IP `10.0.0.99` | `REG_LAST_DST_IP = 0x0A000063` ✓ |
| dst port `9000` | `REG_LAST_PORTS` low 16 = `0x2328` ✓ |
| stock_locate `0x1234` | `REG_LAST_STOCK_LOCATE = 0x00001234` ✓ |
| ref_num `0x0123ABCD000186A5` | `REG_LAST_REF_NUM_HIGH/LOW = 0x0123ABCD / 0x000186A5` ✓ |
| shares `1004` | `REG_LAST_SHARE_AMT = 0x000003EC` ✓ |
| stock_sym `"AAPL    "` | `REG_LAST_STOCK_SYM_HIGH/LOW = 0x4141504C / 0x20202020` ("AAPL"+spaces) ✓ |
| price `9989684` | `REG_LAST_PRICE = 0x00986E34` ✓ |
| sequence `5` | `REG_LAST_SEQ_LOW = 0x00000005` ✓ |

---

## 13. Engineering Notes and Bring-Up Debug Narrative

This section captures the non-obvious engineering decisions and the debug narrative behind the FPGA bring-up. Documenting these is part of the deliverable both because they were the hardest single-issue bugs to track down and because the diagnostic methodology used to find them is reusable.

### 13.1 Why PCS loopback (not PMA)

The Xilinx UltraScale+ GT has five loopback modes selectable via the 3-bit `gt_loopback_in` signal:

| Encoding | Mode | Where the loop happens |
|---|---|---|
| `3'b000` | Normal | No loopback |
| `3'b001` | Near-end PCS | Digital, after PCS encoding, before SerDes |
| `3'b010` | Near-end PMA | Analog, at the SerDes |
| `3'b100` | Far-end PMA | Received signal looped back out |
| `3'b110` | Far-end PCS | Same, at PCS level |

We initially used `3'b010` (near-end PMA) on the belief that it was the most realistic self-test mode. The link came up, but every UDP packet we sent reached the parser as a single-beat frame with `tlast` asserted on the first beat — regardless of the actual packet length on the wire. This made the parser's beat-1 branch unreachable; no ITCH parsing fired.

Switching to `3'b001` (near-end PCS) eliminated the issue. PCS loopback is bit-perfect because it bypasses the SerDes alignment machinery entirely, which is sensitive to having no real link partner.

The hard-coded constant lives at `src/cmac_subsystem/cmac_subsystem_cmac_wrapper.sv` line 305:

```verilog
assign gt_loopback_in = {4{3'b001}};
```

The wrapper drives this signal directly to the four GT lanes of the CMAC. The CMAC IP's internal AXI-Lite `GT_LOOPBACK_REG_0` register at IP offset `0x90` is not connected to this signal in the OpenNIC integration (verified by inspection), so writing it via `bar_write 0x8090 0x00002222` had no effect during bring-up.

### 13.2 The pm_tick fix

The CMAC IP's stat counter snapshot is gated by `pm_tick`, which in stock OpenNIC is hardwired to `1'b0`. With `pm_tick` never asserting, all stat counters readable via AXI-Lite return their power-on values regardless of how many packets actually passed through.

For runtime instrumentation we replaced the hardwired tie-off with a free-running divider:

```verilog
reg [15:0] pm_tick_div;
always @(posedge cmac_clk) pm_tick_div <= pm_tick_div + 1'b1;
assign pm_tick = &pm_tick_div;     // pulses once every 2^16 cmac_clk cycles ≈ 204 µs
```

This pulses `pm_tick` well below the IP's required sub-millisecond cadence and above its minimum 4-cycle pulse spacing.

### 13.3 The byte-ordering bug

**The symptom.** After PCS loopback was working and `REG_PACKET_COUNT` was rising in lock-step with `send_itch.py` invocations, `REG_PARSED_MSG_COUNT` remained stubbornly at zero. The diagnostic counters showed:

- `REG_DBG_BEAT0_COUNT` rising in lock-step with `REG_PACKET_COUNT` (parser enters Beat-0 for every packet)
- `REG_DBG_BEAT1_COUNT` rising as expected for multi-beat packets
- But `REG_DBG_LAST_MSG_TYPE` reading `0x00` instead of `0x41`

**The diagnostic test.** We sent a UDP packet whose entire 1000-byte payload was the byte `0x41`. If the parser was reading the *wrong byte position* of a normal ITCH packet (where `0x41` lives only at byte 64), then an all-`0x41` packet should make the parse fire from any position the parser was reading. It did:

```
REG_PARSED_MSG_COUNT       0 → 25
REG_COUNT_ADD_ORDER        0 → 75       (case 0x41 fired many times)
REG_LAST_SRC_IP            10.0.0.3 → 40.35.154.223     ← byte-reversed!
REG_LAST_DST_IP            10.0.0.99 → 99.0.0.10        ← byte-reversed!
```

The IPs were captured in the *reverse* byte order from what the sender used. That's the smoking gun.

**The root cause.** From Xilinx PG203 (UltraScale+ Integrated 100G Ethernet Subsystem), the CMAC AXI-Stream interface places **byte 0 of the packet at `tdata[7:0]`** (little-endian byte placement on the bus). The parser code was written assuming **byte 0 at `tdata[511:504]`** (big-endian / network-order). Every field-extract offset in the parser was reading the wrong 6-byte / 4-byte / 2-byte window — except for the all-`0x41` test where every byte was `0x41` regardless of position.

**The fix.** Rather than rewrite every offset in the parser, we reverse the byte order at the boundary:

```verilog
wire [511:0] tdata_be;
generate
    for (genvar bi = 0; bi < 64; bi = bi + 1) begin : g_tdata_swap
        assign tdata_be[8*(63 - bi) +: 8] = s_axis_cmac_rx_tdata[8*bi +: 8];
    end
endgenerate
```

Every read inside the parser then uses `tdata_be` in place of `s_axis_cmac_rx_tdata`. The fix lives in `plugin/p2p/packetparser_322mhz_simple.sv`.

After this fix, the §10 end-to-end demo produces the correct output for every field on the first run.

### 13.4 Diagnostic counters as a methodology

The byte-ordering bug would have been substantially harder to find without the seven diagnostic registers added during bring-up. The reusable principle: when a downstream counter (`REG_PARSED_MSG_COUNT`) refuses to move and the upstream counter (`REG_PACKET_COUNT`) is moving correctly, add intermediate counters that progressively localize where in the FSM the signal disappears. Specifically:

- `BEAT_COUNT` — total valid beats (independent of FSM state)
- `BEAT0_COUNT` — entries into the header-parse branch
- `BEAT1_COUNT` — entries into the payload-parse branch
- `LAST_MSG_TYPE_SEEN` — the actual byte at the position the parser reads from
- `LAST_TKEEP_ON_TLAST` — the per-byte validity mask on packet-end

Combined, these counters answered "did the FSM enter beat 1?" (yes, from `BEAT1_COUNT` rising) and "what byte is at the parser's read position?" (`0x00`, from `LAST_MSG_TYPE_SEEN`). Those two facts together identified byte-ordering as the cause without requiring an internal logic analyzer (ILA) or a rebuild.

### 13.5 Why the parser sees CMAC RX directly (not via the adapter)

The packet adapter in OpenNIC's C2H path can be configured to prepend a per-packet metadata header (16–22 bytes) before handing packets up to QDMA. If the parser tapped this post-adapter path, every parsed offset would be shifted by the metadata length and would need accounting.

The parser instead taps `s_axis_cmac_rx_*` *before* the adapter, so it sees raw Ethernet frames as the CMAC presents them. This is intentional and architecturally consistent with the "tap, don't transform" design philosophy.

---

## 14. Known Limitations and Future Work

### 14.1 Loopback-only end-to-end testing

The FPGA parser has only been exercised under PCS internal loopback. We have not connected the U55C to an external 100 Gigabit Ethernet source. The PCS-loopback path exercises the full CMAC RX datapath, AXI-Stream presentation, and parser FSM exactly as a real link partner would, but cannot validate link-layer behaviors that depend on remote-end alignment (auto-negotiation, FEC convergence under bit errors, etc.).

### 14.2 Tier-3 multi-message coverage

The simple parser handles up to 2 ITCH messages per MoldUDP64 packet (Tier 3). Production NASDAQ feeds can pack more. Extending to N-message packets requires generalizing the cross-beat completion FSM in `packetparser_322mhz_simple.sv`.

### 14.3 CPU runs only in simulation

The custom-instruction RISC-V core has been exercised exclusively in cycle-accurate VCS simulation on EWS. The baseline core uses Synopsys DesignWare IP (`DW02_mult`, `DW_div_seq`), which is ASIC-only and unsynthesizable on Vivado. Porting to FPGA requires either dropping the M-extension (multiply/divide) or replacing the DesignWare IP with Xilinx-native multiplier/divider primitives — neither is technically difficult, just out of scope for this semester.

### 14.4 Closed-system integration

The two halves of the project — parser and CPU — share a logical model (the parser produces what the CPU reads via `fetch_trade`) but are not physically wired together. A fully integrated demonstration would place a stripped-down RV32I core directly into OpenNIC's Box0 region, wire the parser's output stream to the CPU's `fetch_trade` BRAM, and run the full closed loop on a single FPGA. The stub plugin scaffolding for Box0 is in place (`plugin/cpu/cpu_stub.sv`); it currently returns a static "RISC" magic value via BAR2 and is a placeholder for the real core.

### 14.5 No real-exchange feed

We exercised the parser against synthetic MoldUDP64 packets emitted by `send_itch.py`, not against a real exchange feed. The synthetic packets follow the NASDAQ ITCH spec layout exactly, but a real-world deployment would need additional handling for retransmission protocols (MoldUDP64 gap-fill, etc.) that are out of scope here.

---

## 15. References

1. **NASDAQ TotalView-ITCH 5.0 Specification.** Defines the binary message layout for `0x41` Add Order, `0x69` Add Order with MPID, `0x68` Stock Trading Action, and other ITCH message types. Used as the authoritative source for parser field offsets.

2. **NASDAQ MoldUDP64 Specification.** Defines the UDP-encapsulated framing of ITCH messages: 10-byte session id, 8-byte sequence number, 2-byte message count, then per-message {2-byte length, payload} pairs.

3. **Xilinx PG203 — UltraScale+ Devices Integrated 100G Ethernet Subsystem Product Guide.** Documents the CMAC AXI-Stream interface convention (byte 0 at `tdata[7:0]`), the loopback mode encodings, the stat-counter pm_tick requirement, and the IP register map.

4. **Xilinx OpenNIC framework.** [github.com/Xilinx/open-nic](https://github.com/Xilinx/open-nic), [github.com/Xilinx/open-nic-shell](https://github.com/Xilinx/open-nic-shell), [github.com/Xilinx/open-nic-driver](https://github.com/Xilinx/open-nic-driver). Our forks live in this project's `open-nic-shell/` submodule.

5. **NASDAQ OUCH 5.0 Specification.** Order-entry protocol used as the message format for the OUCH-shaped frames in the CPU side's two-protocol demonstration.

6. **RISC-V Unprivileged ISA Specification, v2.2.** Defines the `custom-0` through `custom-3` opcode space (`0x0B`, `0x2B`, `0x5B`, `0x7B`) used for `fetch_trade` (custom-1) and `pkt_w` / `pkt_s` / `pkt_st` (custom-2).

---

*End of report.*
