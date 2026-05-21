# Accelerating the Tick-to-Trade Critical Path through Custom RISC-V Instructions and FPGA-Based Ethernet Parsing for High-Frequency Trading

**IE497, Spring 2026 — Independent Project Report**

---

## Abstract

 In industries like High-Frequency Trading (HFT), FPGAs have become critical over the past decade because firms rely on speed to analyze market data, respond to order book changes, and execute trades. The faster a firm can carry out a trade, the more relevant it remains, stimulating innovation in hardware acceleration.  A bottleneck in HFT pipelines is the connection between the custom FPGA logic and a general-purpose CPU. After data is parsed in hardware, it is handed off to the CPU through interrupts, memory-mapped buffers, or system calls, all of which add latency. This project explores how we can improve that interface. Specifically, we’re interested in how adding custom instructions to a RISC-V softcore can improve latency. We want to measure how much faster the CPU can access parsed market data using custom instructions compared to traditional memory-mapped I/O or software-based routes. 


We have designed a two-stage architecture that moves both ends of the tick-to-trade pipeline onto dedicated hardware. A custom RISC-V processor is extended with four new instructions that bypass the standard memory-access path: one reads pre-parsed market-data fields from an on-chip buffer and three more compose a transmit primitive that lets software stage Ethernet order frames and fire them with a single instruction. We use simulation to measure the cycle latency to compare different methods. On the network side, a Verilog packet-parser plugin synthesized into the OpenNIC framework on a Xilinx Alveo U55C decodes MoldUDP64-encapsulated ITCH messages from the 100-gigabit Ethernet interface and exposes the parsed fields to host software through PCIe-readable status registers, removing software decoding from the critical path. The two subsystems together quantify the latency gains achievable by creating dedicated hardware for tasks typically done in software 

---

## Table of Contents

0. [Fresh Clone Checklist](#0-fresh-clone-checklist)
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
12. [Engineering Notes and Bring-Up Debug Narrative](#12-engineering-notes-and-bring-up-debug-narrative)
13. [Known Limitations and Future Work](#13-known-limitations-and-future-work)
14. [References](#14-references)

---

## 0. Fresh Clone Checklist

Below we have included steps for getting started. 

```bash
# (1) Clone with submodules. ${CLONE_PATH} is wherever you want the repo to sit         see §5
git clone --recursive https://gitlab.engr.illinois.edu/ie497_ie597_independent_study_spring_2026/ie497_spring_2026_group_01/group_01_project.git ${CLONE_PATH}                                
cd ${CLONE_PATH}

# (2) Source Vivado on the build machine. Adjust this version based on what your machine has
source /tools/Xilinx/Vivado/2024.2/settings64.sh 
vivado -version                                                  

# (3) Build the parser bitstream inside tmux. Ctrl-B D to detach.      see §8
tmux new -s build_parser
cd open-nic-shell/script
vivado -mode batch -source ./build.tcl -tclargs \
    -board au55c -tag final \
    -user_plugin ../plugin/p2p \
    -impl 1 -post_impl 1 -overwrite 1 -jobs 8 \
    2>&1 | tee ../build_final.log
# tmux attach -t build_parser to reconnect. 


# (4) Install the four root-owned wrappers. One-time per host. Only needed if you don't have sudo access       see §5.1
sudo install -m 0755 -o root -g root open-nic-shell/script/setup_device.sh  /usr/local/bin/setup_open_nic_device
sudo install -m 0755 -o root -g root open-nic-shell/script/program_fpga.sh  /usr/local/bin/program_open_nic_fpga
sudo install -m 0755 -o root -g root open-nic-shell/script/bar_read.py      /usr/local/bin/bar_read
sudo install -m 0755 -o root -g root open-nic-shell/script/bar_write.py     /usr/local/bin/bar_write


# (5) Program the FPGA.                                              see §9
lspci -nn -d 10ee:903f # Example: 83:00.0 Memory controller [0580]: Xilinx Corporation Device [10ee:903f]

# Then set EXTENDED_DEVICE_BDF1 to "0000:<bus>:<dev>.<func>" from above line.
export EXTENDED_DEVICE_BDF1=0000:83:00.0
sudo -E /usr/local/bin/program_open_nic_fpga \
    open-nic-shell/build/au55c_final/open_nic_shell/open_nic_shell.runs/impl_1/open_nic_shell.bit \
    au55c

# (6) Clone repo and load the onic driver
git clone https://github.com/Xilinx/open-nic-driver ${DRIVER-PATH}
cd ${DRIVER-PATH}
sudo insmod onic.lo

# (7) Configure the network interface + static ARP. # The values we have picked below are choices made for our loopback test and can be changed.                                            see §5.3, §9.5
# IFACE: netdev name Linux assigns to the U55C after `modprobe onic`. hft03 default: ens2
# HOST_IP: host-side address on the loopback subnet. Any unused address in a private /24 works; we picked 10.0.0.3 because the lab doesn't route 10.0.0.0/8 anywhere else.
# DST_IP: destination for outbound test packets. 
# DST_MAC a locally-administered MAC (02:* = no real OUI) we statically map to DST_IP so the kernel transmits UDP without waiting on an ARP reply that will never come. The trailing :99 is a mnemonic matching the .99 of DST_IP.

ip -br link
IFACE=ens2 
HOST_IP=10.0.0.3/24
DST_IP=10.0.0.99
DST_MAC=02:00:00:00:00:99

sudo ip link set "$IFACE" up
sudo ip addr add "$HOST_IP" dev "$IFACE"
sudo arp -i "$IFACE" -s "$DST_IP" "$DST_MAC"

# (8) Sanity-check the parser is reachable. 
export OPENNIC_BDF=<your-bdf>  # find the right PCIe device (see §5.2).                         see §9.6
sudo bar_read 0x200000      # expect: 0x49544348  ("ITCH")

# (9) Run the end-to-end demo.                                       see §10
python3 open-nic-shell/script/read_parser_regs.py > /tmp/before.txt
python3 open-nic-shell/script/send_itch.py --src-ip "$HOST_IP" --dst-ip "$DST_IP" --count 5 --interval 0.2
python3 open-nic-shell/script/read_parser_regs.py > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
```

The remainder of the report explains why each step looks like this, what failure modes to watch for, and what the expected results are.

---

## 1. Project Overview

### 1.1 Problem statement

In a conventional pipeline, getting market data into a CPU register and getting an order back out onto the wire both rely on general-purpose mechanisms that pay the full cost of the load-store unit and the kernel:

- If parsing is done in software, the CPU walks the raw NASDAQ ITCH / MoldUDP64 byte stream itself — extracting the message type, stock locate, price, and shares with general-purpose loads, shifts, and branches.
- If parsing has already been offloaded to an accelerator, the CPU still has to read the parsed fields back via memory-mapped I/O. Each lw traverses the load-store unit, the cache hierarchy, and the PCIe root complex before reaching the accelerator's register file.
- Emitting the outbound order goes through the kernel networking stack — a system call, an sk_buff allocation, a user-to-kernel copy, and a doorbell write to the NIC.

Each of these uses a general-purpose mechanism (cache-traversing load, kernel transition, full instruction-fetch pipeline) for what is, semantically, a single data transfer.

The thesis question this project investigates is: if each of these is instead expressed as a dedicated RISC-V instruction backed by on-chip hardware, how much shorter does the critical path become — measured in CPU cycles on an apples-to-apples comparison against the conventional software-parse and MMIO baselines of the same workload?

### 1.2 Two-stage architecture

The system is co-designed in two halves that can be reasoned about and validated independently:

```
┌────────────────────────────────────────────────────────────────────────────────┐
│            Custom RV32IM Out-of-Order Core  (VCS simulation, EWS)              │
│                                                                                │
│   Fetch ──▶ Decode ──▶ Rename ──▶ Dispatch                                     │
│                                       │                                        │
│                                       ▼                                        │
│    ┌──────────────────────────────────────────────────────────────────────┐    │
│    │  Rename / Retire State                                               │    │
│    │     RAT  ·  PRF (64 physical × 32 b)  ·  ROB (32 entries → RRAT)     │    │
│    └─────────────────────────▲──────────────────────────────▲─────────────┘    │
│                              │ operand read                 │ writeback        │
│                              │                              │                  │
│    ┌─────────────────────────┴───┐    ┌─────────────────── CDBs ──────────┐    │
│    │  Reservation Stations       │    │                                   │    │
│    │   RS_ALU    ─────────────▶  │    │  ALU  ┐                           │    │
│    │   RS_BR     ─────────────▶  │    │  BR   ├──▶ cdb_alu_br  ───────────┼───▶│
│    │   RS_MEM    ─────────────▶  │───▶│  MEM  ────▶ cdb_mem    ───────────┼───▶│
│    │   RS_MUL    ─────────────▶  │    │  MUL ┐                            │    │
│    │   RS_DIV    ─────────────▶  │    │  DIV ┤  priority arb              │    │
│    │   RS_TRADE  ─────────────▶  │    │  FT  ┤  + 1-deep bufs             │    │
│    │   RS_PKTTX  ─────────────▶  │    │  PT  ┘ ──▶ cdb_mul_div ───────────┼───▶│
│    └─────────────────────────────┘    └───────────────────────────────────┘    │
│                                                                                │
│──── fetch_trade FU backing store ──────────────────────────────────────────────│
│                                                                                │
│     xpm_memory_sdpram  ·  8 packets × 8 slots × 32 bit                         │
│      Port A (write) ◀── behavioral parser (hvl/common/fake_packet_parser.sv)   │
│      Port B (read)  ◀── FT FU returns slot to cdb_mul_div in 2 cycles          │
│                                                                                │
│──── pkt_tx FU backing store ───────────────────────────────────────────────────│
│                                                                                │
│     Staging BRAM  ·  8 slots × 16 words × 32 bit                               │
│      Port A (write) ◀── PT FU, one word per pkt_w                              │
│      Port B (read)  ──▶ drain FSM (IDLE → SEND → IDLE on pkt_s)                │
│                                       │                                        │
│                                       ▼                                        │
│                          AXI-Stream master (m_axis_pkt_tx_*)                   │
│                          1 × 32-bit beat per cycle  ──▶ order frame            │
└────────────────────────────────────────────────────────────────────────────────┘

```

```
┌────────────────────────────────────────────────────────────────────────────────┐
│      Xilinx Alveo U55C   ·   OpenNIC framework   ·   our plugin in Box1        │
│                                                                                │
│   Wire (QSFP)                                                                  │ 
│       │                                                                        │
│       ▼                                                                        │
│   ┌───────────────────────────┐                                                │
│   │ 100G CMAC subsystem       │                                                │
│   │ Xilinx UltraScale+ IP     │                                                │
│   │ PCS internal loopback     │                                                │
│   └───┬────────────────────▲──┘                                                │
│       │ RX (512 b @ 322MHz)│ TX                                                │
│       ▼                    │                                                   │
│   ┌────────────────────────────────────────────────────────────────────────┐   │
│   │   Box1 @ 322 MHz  —  plugin/p2p/p2p_322mhz.sv                          │   │
│   │                                                                        │   │
│   │     parser snoop on s_axis_cmac_rx ──▶ pass-through to adapter ──────┐ │   │
│   │            │                                                         │ │   │
│   │            ▼                                                         │ │   │
│   │     packetparser_322mhz_simple.sv                                    │ │   │
│   │       decodes  Ethernet → IPv4 → UDP → MoldUDP64 → ITCH              │ │   │
│   │       msg types 'A' (0x41), 'i' (0x69), 'h' (0x68)                   │ │   │
│   │            │                                                         │ │   │
│   │            ▼  parsed fields                                          │ │   │
│   │     Shadow registers   (axil_aclk domain, CDC from cmac_clk)         │ │   │
│   │       ├─ REG_MAGIC = 0x49544348 ("ITCH")                             │ │   │
│   │       ├─ REG_LAST_* (msg_type, price, shares, sym, ref_num, IP…)     │ │   │
│   │       ├─ REG_COUNT_* (per-type counters)                             │ │   │
│   │       └─ REG_DBG_*   (7 diagnostic counters, see §13.4)              │ │   │
│   │            │                                                         │ │   │
│   │            ▼                                                         │ │   │
│   │     AXI-Lite slave   ─── 33 regs at BAR2 0x200000–0x2000FF.          │ │   │
│   └──────────────┬───────────────────────────────────────────────┬───────┬─┘   │
│                  │ AXI-Lite                                      │       │     │
│                  ▼                                               ▼       │     │
│         OpenNIC AXI-Lite crossbar                Packet adapter (250 MHz)│     │
│                  │                                               │       │     │
│                  │                                               ▼       │     │
│                  │                                       ┌─────────────┐ │     │
│                  │                                       │  QDMA (PCIe │◀┘     │
│                  │                                       │  Gen3)      │       │
│                  │                                       └──────┬──────┘       │
│                  │ PCIe (BAR2 MMIO)                             │ PCIe (data)  │
│                  ▼                                              ▼              │
│   ┌──────────────────────────────────────────────────────────────────────┐     │
│   │ Host (hft03, Linux)                                                  │     │
│   │   • onic driver → netdev ens2  (kernel TX/RX through QDMA)           │     │
│   │   • send_itch.py emits MoldUDP64+ITCH UDP via ens2 (loops at CMAC)   │     │
│   │   • bar_read / read_parser_regs.py read parsed fields out of BAR2    │     │
│   └──────────────────────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────────────────┘

```

The FPGA side is validated on real silicon (Xilinx U55C, PCIe-attached). The CPU side is validated via cycle-accurate simulation in Synopsys VCS.

### 1.3 Headline results

This section overviews what we measured and what each measurement was designed to answer. All CPU cycle numbers are from VCS simulation on EWS and nanosecond measurements approximated assuming the 322 MHz CMAC clock.

#### 1. Custom instruction vs MMIO vs software (RX-side baseline)

We created three firmware implementations of the same ITCH decision predicate: [itch_software.c](riscv-cpu/testcode/sim_b/itch_software.c) parses raw bytes in software, [itch_mmio.c](riscv-cpu/testcode/sim_b/itch_mmio.c) reads pre-parsed fields via `lw` from a memory-mapped BRAM, and [itch_custom.c](riscv-cpu/testcode/sim_b/itch_custom.c) reads the same fields via the new `fetch_trade` instruction. 


| Path | Single-shot (cyc) | Steady-state (cyc/event) | ILP-saturated (cyc/event) |
|---|---|---|---|
| Software parse | 234 | 55.0 | 51.2 |
| MMIO `lw` | 105 | 29.0 | 27.1 |
| `fetch_trade` | **59** | **26.0** | 27.1 |

Then we ran a single-shot, swept over ITER ∈ {1, 10, 100, 1000} for steady-state and re-measured under an ILP-saturated mixed workload.

| Custom Instruction Speedup | vs MMIO | vs software |
|---|---|---|
| Single-shot | **1.78×** | **4.0×** |
| Steady-state | 1.12× | 2.12× |
| ILP-saturated | 1.00× | 1.89× |


These benchmarks are meant to show that the lifting an  read out of the LSU/cache/PCIe path into a dedicated functional unit produce a measurable cycle. 

#### 2. FPGA parser end-to-end on silicon

[send_itch.py](open-nic-shell/script/send_itch.py) emits real MoldUDP64-encapsulated ITCH Add Order packets through the host kernel into the `ens2` netdev; the 100 G CMAC loops them back via PCS internal loopback; the parser in [packetparser_322mhz_simple.sv](open-nic-shell/plugin/p2p/packetparser_322mhz_simple.sv) decodes Ethernet → IPv4 → UDP → MoldUDP64 → ITCH; [read_parser_regs.py](open-nic-shell/script/read_parser_regs.py) reads every decoded field out of BAR2.

Every result above this point is simulation. This is the one result that runs on real hardware (Xilinx Alveo U55C in `hft03`).

**Result.**

| Sender wrote | Parser decoded | Match |
|---|---|---|
| `msg_type = 'A'` | `REG_LAST_MSG_TYPE = 0x41` | ✓ |
| `buy_sell = 'B'` | `REG_LAST_BUY_SELL = 0x42` | ✓ |
| src/dst IP `10.0.0.3` / `10.0.0.99` | `0x0A000003` / `0x0A000063` | ✓ |
| `stock_locate = 0x1234` | `REG_LAST_STOCK_LOCATE = 0x1234` | ✓ |
| `ref_num = 0x0123ABCD000186A5` | `REG_LAST_REF_NUM_HIGH/LOW` matches | ✓ |
| `shares = 1004` | `REG_LAST_SHARE_AMT = 0x000003EC` | ✓ |
| `stock_sym = "AAPL    "` | `REG_LAST_STOCK_SYM_*` = `"AAPL" + spaces` | ✓ |
| `price = 9989684` | `REG_LAST_PRICE = 0x00986E34` | ✓ |
| `sequence = 5` | `REG_LAST_SEQ_LOW = 0x00000005` | ✓ |

The full field-by-field comparison from a 5-packet demo run is in §12.3.

## 2. Repository Structure

```
ie497/                                 ← top-level project repo
├── README.md                          ← this document
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

The two subprojects are independent — the CPU sim does not depend on the FPGA build, and vice versa. They share an architectural model (the parser drives the same field layout the CPU side reads)

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

#### Vivado

The Vivado installation used for the final parser bitstream lives at the standard Xilinx lab path on `hft06`. Sourcing the settings script makes `vivado` available on the shell `PATH`:

```bash
# On hft06, before launching any build:
source /tools/Xilinx/Vivado/2024.2/settings64.sh

# Verify what is now active:
which vivado
vivado -version
echo "$XILINXD_LICENSE_FILE"
echo "$LM_LICENSE_FILE"
```

The final parser bitstream was built with **Vivado 2024.2** on `hft06`. The installation lives at `/tools/Xilinx/Vivado/2024.2/`, and the `vivado` binary used is `/tools/Xilinx/Vivado/2024.2/bin/vivado`. The build TCL is version-agnostic — any UIUC Vivado lab install that supports the `au55c` board file and the 100G CMAC v3.1 IP will produce an equivalent bitstream — but the table below reflects the specific install we exercised.

XRT (Xilinx Runtime) is **not** required for this project's tested flow. The parser is programmed via Vivado's hardware manager invoked from `program_fpga.sh`, and host-side access is through `/sys/bus/pci/.../resource2` and the standard `onic` kernel module — neither path uses XRT.

#### Full tool inventory

| Tool | Where used | Version | Notes |
|---|---|---|---|
| Xilinx Vivado | `hft06` (parser bitstream); `hft03` available as backup | **2024.2** (`/tools/Xilinx/Vivado/2024.2/bin/vivado`) | Source `/tools/Xilinx/Vivado/2024.2/settings64.sh` before running the build. |
| Xilinx 100G CMAC IP | inside Vivado | v3.1 (`CONFIGURATION_REVISION_REG = 0x00000301` confirmed via BAR read after bring-up) | Licensed; available through the campus Xilinx license server. |
| Synopsys VCS | EWS workstations | as installed on EWS (2024.x line) | invoked through the CPU repo's existing `sim/Makefile`. No build customization. |
| RISC-V GCC | EWS workstations | `riscv64-unknown-elf-gcc` from the EWS toolchain (run `riscv64-unknown-elf-gcc --version` to capture) | `--march=rv32i_zicsr --mabi=ilp32` after the M-extension was deleted; `rv32im` on the original baseline branch. |
| Python | `hft03`, `hft06`, EWS | 3.8 or newer | `bar_read.py`, `bar_write.py`, `read_parser_regs.py`, `send_itch.py`, `send_raw_bytes.py` are pure Python 3, no external packages required. |
| `setpci`, `lspci`, `tcpdump`, `ethtool`, `ip`, `arp` | `hft03` | system default (Ubuntu) | Used during programming and bring-up. |
| XRT | _not used_ | — | The OpenNIC flow does not depend on XRT. |

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

The BDF values are stable across reboots on `hft03`. They are the **defaults** baked into `bar_read.py` and `bar_write.py`; both helpers honor the `OPENNIC_BDF` environment variable to override the default on any other host (see §5.2). `program_fpga.sh` reads the BDF from the `EXTENDED_DEVICE_BDF1` environment variable that the operator exports before invoking it.

---

## 4. Required Privileges and Sudoers Configuration

The OpenNIC programming flow and BAR-region access both require root for specific operations. To allow non-root team members to perform reproducible programming and register reads without password prompts, the lab administrator (the course instructor in our case) installs a scoped sudoers entry.

### 4.1 The sudoers entry installed on `hft03`

File: `/etc/sudoers.d/sp26-ie497-dl-grp01`

```
%sp26-ie497-dl-grp01 ALL=(ALL) NOPASSWD: /usr/local/bin/setup_open_nic_device *
%sp26-ie497-dl-grp01 ALL=(ALL) NOPASSWD: /usr/local/bin/program_open_nic_fpga *
%sp26-ie497-dl-grp01 ALL=(ALL) NOPASSWD: /usr/local/bin/bar_read *
%sp26-ie497-dl-grp01 ALL=(ALL) NOPASSWD: /usr/local/bin/bar_write *
```

**Design note.** Every path in the rule is a system-level absolute path under `/usr/local/bin/`. Nothing points into any user's home directory. The four binaries referenced are root-owned 0755 wrappers installed once per host from the repository (see §5.1). This satisfies the design requirement that no reproducible step depend on a particular user's account name.

### 4.2 What each grant covers

- **`setup_open_nic_device *` and `program_open_nic_fpga *`** — Root-owned 0755 wrappers around the repo's `script/setup_device.sh` and `script/program_fpga.sh`. They internally call `setpci`, `tee /sys/bus/pci/devices/.../remove`, `tee /sys/bus/pci/devices/.../rescan`, and `rmmod` / `insmod` on the `onic` kernel module. Granting NOPASSWD on the *wrappers* (rather than on each underlying system command) keeps the privilege footprint tight. Because the wrappers are root-owned and not writable by unprivileged users, group members cannot edit them to escape the intended scope.

- **`/usr/local/bin/bar_read *` and `/usr/local/bin/bar_write *`** — Python helpers (described in §7.5) that `mmap`-read or `mmap`-write 32-bit words from BAR2 of a specific PCIe device, with bounds checking against the BAR size reported by `fstat`. The 4-byte access size and the per-call BAR-size verification make them safe to expose at group level. They honor the `OPENNIC_BDF` environment variable (defaulting to `0000:83:00.0` for `hft03`'s U55C) so the same binaries work on any host whose U55C is enumerated at a different bus/device/function.

The scoped wildcard `*` after each rule lets group members pass arbitrary register offsets and (for `bar_write`) values, while still preventing them from invoking any other binary on the system through sudo.

### 4.3 Membership requirement

The user account performing FPGA bring-up must be a member of the Unix group `sp26-ie497-dl-grp01`. Verify with:

```bash
id | tr ',' '\n' | grep sp26-ie497-dl-grp01
```

If the group does not appear, log out and back in (the group may have been added after the current session started) or request membership from the course instructor.

### 4.4 No CPU-side privileges required

The cycle-accurate RISC-V simulation runs entirely as the user on EWS. No sudo is needed for anything in the `riscv-cpu/` subtree.

---

## 5. Cloning and Initial Setup

The repository is hosted on UIUC's GitLab. Clone with submodules:

```bash
# Choose any clone location — the project does not assume a specific path.
# All repo-level commands below are written relative to the clone root.

git clone --recursive https://gitlab.engr.illinois.edu/ie497_ie597_independent_study_spring_2026/ie497_spring_2026_group_01/group_01_project.git ie497
cd ie497

# If you cloned without --recursive, fetch the submodules now:
git submodule update --init --recursive
```

This brings down both subprojects:

- `open-nic-shell/` — fork of Xilinx OpenNIC with the parser plugin and CMAC-wrapper modifications
- `riscv-cpu/` — the custom RV32IM out-of-order core with the four custom instructions

**Path convention used throughout this document.** All repo-level commands are written relative to the clone root, which we refer to as `${PROJECT_ROOT}`. System-level commands intentionally use system absolute paths (`/usr/local/bin`, `/sys/bus/pci`, `/tools/Xilinx`, `/etc/sudoers.d`) because those locations are fixed by the operating system and the Xilinx tool layout, not by who installed them. **No command in this document depends on a specific user's home directory.** Anywhere a user might have been tempted to embed a `/home/<user>/...` path — sudoers rules, kernel-module paths, build artifacts — the document instead points at a root-owned `/usr/local/bin/` wrapper or a `find` command that discovers the real location at run time.

### 5.1 Adding the BAR helpers to the system path on `hft03`

Required only once per host, after the first clone or after a `git pull` that touches any of these files. From the clone root:

```bash
sudo install -m 0755 -o root -g root open-nic-shell/script/setup_device.sh  /usr/local/bin/setup_open_nic_device
sudo install -m 0755 -o root -g root open-nic-shell/script/program_fpga.sh  /usr/local/bin/program_open_nic_fpga
sudo install -m 0755 -o root -g root open-nic-shell/script/bar_read.py      /usr/local/bin/bar_read
sudo install -m 0755 -o root -g root open-nic-shell/script/bar_write.py     /usr/local/bin/bar_write
```

These four `install` commands need root once each, but afterwards the scoped sudoers rule in §4 allows any member of `sp26-ie497-dl-grp01` to invoke the installed binaries without a password. The installed copies are root-owned and detached from any user's home directory.

### 5.2 (Optional) Override the PCIe BDF for a different host

`bar_read` and `bar_write` default to BDF `0000:83:00.0` (the U55C on `hft03`). On any other host whose U55C is at a different BDF, export `OPENNIC_BDF` before invoking the helpers:

```bash
# one-time per shell on a different host:
export OPENNIC_BDF=0000:af:00.0   # whatever lspci shows for the U55C on that host

# subsequent invocations:
sudo -E bar_read 0x200000          # the -E preserves the env var across sudo
```

`read_parser_regs.py` invokes `bar_read` as a subprocess, so the same `OPENNIC_BDF` export reaches it via the inherited environment.

### 5.3 Host network configuration on `hft03`

After the FPGA is programmed (§9), the OpenNIC interface enumerates as a Linux netdev. We configure it for an isolated loopback test subnet, with a manual ARP entry so the kernel will transmit UDP without ARP resolution depending on a (deliberately absent) network partner:

```bash
# All four of these are project choices, not physical constants.
# Adjust if your environment requires different values.

IFACE=ens2                       # netdev name on hft03 after `modprobe onic`
HOST_IP=10.0.0.3/24              # this host's address on the test subnet
DST_IP=10.0.0.99                 # synthetic destination for UDP test packets
DST_MAC=02:00:00:00:00:99        # locally-administered MAC for DST_IP

sudo ip link set "$IFACE" up
sudo ip addr add "$HOST_IP" dev "$IFACE"
sudo arp -i "$IFACE" -s "$DST_IP" "$DST_MAC"
```

#### Where each value comes from

- **`IFACE` (default `ens2`).** The Linux kernel assigns this name when the `onic` driver binds to the U55C's PCIe device. The exact name depends on the kernel's *predictable network interface names* rules — bus, slot, function — which are themselves a function of the host's PCIe topology. On `hft03` the U55C lives at BDF `0000:83:00.0` and the resulting netdev is consistently `ens2` across reboots. On any other host, run `ip -br link` after `modprobe onic` and use whatever name appears with a Xilinx MAC OUI (`00:0a:35:...`).

- **`HOST_IP` (default `10.0.0.3/24`).** Our chosen address for the host side of the loopback test subnet. The `10.0.0.0/8` range is RFC 1918 private space; the lab's actual networks use different subnets, so this address never conflicts with real routing. The `.3` is arbitrary — any unused address in an unused `/24` works. The `/24` mask keeps the test subnet small.

- **`DST_IP` (default `10.0.0.99`).** A *deliberately unassigned* destination address. The whole point of this value is that nothing is at `.99`. When `send_itch.py` targets `10.0.0.99`, the Linux kernel routes the packet via `IFACE` (because the destination is in the local `/24` subnet), the packet leaves through CMAC TX, and — because the CMAC is configured for PCS internal loopback (§13.1) — it returns through CMAC RX directly to the parser. No external network partner is involved or needed.

- **`DST_MAC` (default `02:00:00:00:00:99`).** A synthetic destination MAC we statically map to `DST_IP` via `arp -s`. The `02:` prefix marks this as a locally-administered address (the IEEE convention for MACs that don't correspond to a real vendor OUI), so it cannot collide with any factory-assigned MAC. The trailing `:99` mnemonically matches the `.99` of `DST_IP`. **The static ARP entry is the load-bearing piece**: without it, the kernel would broadcast ARP requests for `10.0.0.99`, get no reply (because nothing exists at that address — including ourselves, since `10.0.0.99` is not assigned to our `IFACE`), and eventually drop the queued UDP packets. With the static entry, the kernel believes ARP is already resolved and transmits the UDP frame immediately, which is what we want the parser to see.

#### On a different host

If you are bringing this project up somewhere other than `hft03`:

1. Determine the netdev name from `ip -br link` after the `onic` driver loads, and assign it to `IFACE`.
2. Keep `HOST_IP`, `DST_IP`, and `DST_MAC` unless they conflict with existing routing on your host — they're project choices, not requirements. Any pair of addresses in an unused RFC 1918 `/24` works as long as `HOST_IP` is the host's address on that subnet and `DST_IP` is a different unassigned address in the same `/24`.
3. The `send_itch.py` `--src-ip` and `--dst-ip` arguments must match whatever you set above (see §10).

---

## 6. RISC-V CPU Side: Custom Instructions in Simulation

This section describes the CPU half of the project. Everything described here lives under `${PROJECT_ROOT}/riscv-cpu/` and is exercised by running the existing VCS-based test flow on EWS.

### 6.0 What this core is, in plain terms

The RISC-V processor used for this project is not an off-the-shelf core. It is an out-of-order RV32IM CPU built by us last semester. This semester our goal was to extended it with the four custom instructions described in §6.2 and §6.3. Every pipeline stage, every reservation station, and every commit-bus arbiter in the design is original Verilog written by the team.

**What "out-of-order" means.** The processor does not necessarily execute instructions in the program order they appear. As long as data dependencies are honored, the hardware is free to schedule any *ready* instruction onto any available functional unit, then re-order the results back into program order at the commit stage so that programmer-visible state remains consistent. This contrasts with the simpler "in-order" pipelines used in most teaching cores and in many commercial embedded processors, where instruction *N+1* cannot begin executing until instruction *N* finishes. The benefit of out-of-order issue is that long-latency operations — memory loads that miss in cache, multi-cycle multiplies, or in our case the multi-cycle `fetch_trade` and `pkt_s` custom instructions — can sit in the reservation stations waiting for their operands or for the functional unit to drain, without stalling the entire processor. Independent instructions slide past them and execute in the shadow.

This matters for HFT-style workloads because the decision predicate after a `fetch_trade` (a branch on price/shares) and the frame-build sequence after the decision (a fan-out of `pkt_w` writes) contain a mix of latency-tolerant and latency-critical operations. An OoO pipeline keeps the critical-path work moving while the tolerant work amortizes itself in parallel. The waterfall in §6.5 makes this concrete: a 16-cycle TX drain runs in parallel with the firmware setting up the next decision rather than blocking it.

The core's specific structures and dimensions are:

### 6.1 Baseline core

- Non-superscalar out-of-order RV32IM core with:
  - 32 architectural / 64 physical registers
  - 32-entry ROB
  - Distributed reservation stations (ALU=16, BR=8, MUL=8, DIV=4, MEM=16)
  - Three common data buses: `cdb_alu_br`, `cdb_mul_div`, `cdb_mem`
- Inherited from the team's IE421 final project (graded A); modified to add the custom instructions described below.

### 6.2 Custom-1: `fetch_trade` (RX side)

#### What `fetch_trade` does and why it exists

**What it does.** A single RISC-V instruction that reads one field (price, shares, message type, etc.) of a parsed market-data record directly from a small on-chip buffer and returns it in a general-purpose register. The entire round trip — instruction dispatch, BRAM read, writeback to the register file — completes in two cycles.

**Why we included it.** In a conventional HFT software stack, reading a parsed market field requires a memory-mapped load against a network accelerator's PCIe BAR region. That load traverses the L1 cache, then misses out to L2, then to the IOMMU and the PCIe root complex, and finally lands at the accelerator's register file. Even with the cache warm and the load cracked into the fewest possible micro-ops, this typically costs 50–150 cycles on  x86 processors. We wanted to quantify how much could be saved by lifting this access out of the load-store unit entirely and making it a dedicated instruction with its own functional unit.

**Application.** A trading strategy reacting to NASDAQ ITCH Add Order messages issues `fetch_trade rd, 0` to retrieve the message type byte, branches on whether it is `'A'`, then `fetch_trade rd, 3` for the price, branches on the threshold, then `fetch_trade rd, 2` for the shares. Each of these reads is one instruction — versus the multiple-cycle memory-mapped load it replaces. The three-path comparison in §6.4 measures this directly: the same decision predicate takes 59 cycles via `fetch_trade` against 105 cycles via the equivalent memory-mapped load, a 1.78× single-shot speedup.

#### Encoding, semantics, and hardware

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
| 4 | Empty flag (read-only; returns 1 if FIFO empty) |
| 5 | Pop trigger (read advances `tail_ptr`) |
| 6 | Sequence number |
| 7 | Reserved |

**Hardware.** Backed by a single Xilinx `xpm_memory_sdpram` BRAM18 primitive. 8 packets × 8 slots × 32 bits, dual-ported (parser drives Port A, CPU reads Port B). A 4-bit `head_ptr` and `tail_ptr` implement an 8-deep FIFO with empty/full detection. Dispatch-to-CDB latency is 2 cycles. A minimal 4-entry RS holds in-flight `fetch_trade` instructions; no operand wakeup is needed since the instruction has no source register.

**Static benchmark compatibility.** `head_ptr` resets to 1 and the BRAM's `MEMORY_INIT_PARAM` populates packet 0 with constants. This lets the legacy single-shot benchmarks (the three-path baseline) run without the parser stream being active.

### 6.3 Custom-2: `pkt_w` / `pkt_s` / `pkt_st` (TX side)

The three custom-2 instructions together form the **transmit primitive** — the ISA-level mechanism by which firmware composes an outbound Ethernet frame, releases it for emission, and queries hardware completion state. They share opcode `0x2B` (RV custom-2 space), discriminated by `funct3`, with encodings defined in `riscv-cpu/pkg/types.sv`.

| Mnemonic | Source | Destination | Semantics |
|---|---|---|---|
| `pkt_w rs1, imm[3:0]` | `rs1` | none | Writes the 4 bytes of `rs1` into the current staging slot of the TX BRAM, at 32-bit word offset `imm`. |
| `pkt_s rs1` | `rs1` | none | Commits the current staging slot for emission; `rs1` carries the byte length to send (1–64). Advances `staging_ptr`. |
| `pkt_st rd, imm[2:0]` | none | `rd` | Reads one of four status fields (empty / full / busy / pending-count) from the TX subsystem and returns it in `rd`. |

**Shared hardware.** All three instructions operate on a single BRAM holding 8 staging slots × 16 words × 32 bits = 512 bytes. Port A is the CPU write side; Port B feeds an FSM that drains a slot out to an AXI-Stream master interface (`m_axis_pkt_tx_*`) at one 32-bit beat per cycle. The producer (CPU) and consumer (FSM) operate on different slots concurrently, which lets the firmware stage packet *N+1* while hardware is still emitting packet *N*. This decoupling is the architectural advantage of the multi-buffer design over a single-buffer alternative.

#### 6.3.1 `pkt_w` — write packet bytes

**What it does.** Writes 4 bytes of register data into a specific 32-bit word position of the current transmit staging buffer, in one instruction. The 4-bit immediate selects which word (0–15) within the 64-byte staging slot to overwrite. There is no destination register.

**Why we included it.** Constructing an Ethernet frame to transmit is fundamentally a byte-streaming operation — destination MAC, source MAC, ethertype, IPv4 header, UDP header, payload. In conventional software, this work is done by the kernel's networking stack, which incurs system-call overhead per send, copies the payload from user to kernel space, allocates an `sk_buff`, sets up DMA descriptors, and writes a doorbell register to the NIC. We wanted frame composition to happen at ISA level — one instruction per 32-bit word, directly into hardware-attached BRAM, no kernel involvement, no copies.

**Application.** A 64-byte order frame (14 bytes Ethernet + 20 bytes IPv4 + 8 bytes UDP + 22 bytes OUCH order body) is built with exactly 16 `pkt_w` instructions, one per word. The two-protocol demonstration in §6.7 uses the *same* `pkt_w` calls to construct both an ARP request and an OUCH order from a single firmware program — concrete proof that the primitive carries no protocol assumptions.

#### 6.3.2 `pkt_s` — trigger send

**What it does.** Commits the current staging buffer to the transmit queue and tells the hardware FSM to drain the first `rs1` bytes out to the AXI-Stream master interface as an Ethernet frame. The instruction advances `staging_ptr` to the next slot of the eight-slot ring, so the next `pkt_w` writes into a fresh buffer while the FSM independently emits the just-committed one.

**Why we included it.** Triggering a packet send in a conventional software stack means writing a doorbell register on the NIC — itself a memory-mapped store through the same load-store unit and PCIe traversal we already identified as the bottleneck on the RX side. We wanted the send trigger to be a first-class ISA primitive rather than a memory access, both for latency and for clean separation between "compose the frame" and "release the frame."

**Application.** After a strategy has built an OUCH order frame with 16 `pkt_w` instructions, `pkt_s 64` releases it for emission. The eight-buffer architecture lets firmware fire orders back-to-back at the rate of the TX drain (16 cycles per 64-byte frame). The phase-2 multi-buffer overlap benchmark in `itch_send_overlap.c` (§12.1) verifies this: 128 CPU-side writes and 128 hardware-side beats with a measured 16 cycles of overlapping Port-A-write / Port-B-emit activity per packet — the producer and consumer are demonstrably running in parallel.

#### 6.3.3 `pkt_st` — query TX status

**What it does.** Reads one of four hardware status fields and returns the value in `rd`. The 3-bit immediate selects which field. The instruction has no source register, completes in two cycles, and has no side effect on the TX subsystem.

| imm | Field |
|---|---|
| 0 | `tx_empty` — staging FIFO empty AND FSM IDLE (all sends drained) |
| 1 | `tx_full` — next `pkt_s` would stall the RS |
| 2 | `tx_busy` — FSM currently in SEND state |
| 3 | `tx_pending` — count of staged-but-not-drained packets (0–8) |

**Why we included it.** Once the TX subsystem has eight buffers operating asynchronously to the CPU, the firmware needs visibility into hardware state — has the last buffer drained? Is the queue full? — without resorting to fixed delays or to memory-mapped polls. `pkt_st` makes this visibility an ISA-level operation: one instruction, two cycles, hardware state delivered into a register and ready to be branched on.

**Application.** `pkt_st` enables three concrete firmware patterns:

- **End-of-batch synchronization.** Spin on `pkt_st rd, 0` (`tx_empty`) to wait until every packet has finished emitting before stopping a benchmark timer or reporting completion. Without this, the firmware-visible `pkt_s` returns long before the hardware FSM has finished draining, and end-of-batch timing measurements are off by an entire drain window.
- **Back-pressure-aware sending.** Spin on `pkt_st rd, 1` (`tx_full`) before issuing `pkt_s` to avoid a reservation-station stall during burst transmits. This lets the firmware do useful work during back-pressure rather than blocking.
- **Adaptive priority drop.** Read `pkt_st rd, 3` (`tx_pending`) and drop low-priority orders when the queue depth exceeds a threshold — the kind of pattern a production trading strategy uses to degrade gracefully under bursts of incoming market data.


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

### 6.10 Making the core FPGA-synthesizable

All measurements in §6.4–§6.9 were taken on the original RV32IM core in Synopsys VCS on EWS. That core cannot be synthesized in Vivado as-is: the multiplier and divider units depend on Synopsys **DesignWare** IP (`DW02_mult` and `DW_div_seq`), which is provided only as encrypted, ASIC-process-specific blocks. DesignWare is not part of any FPGA tool flow.

As a step toward placing the core onto silicon, we created an alternate branch (`roshnim/cpu-fpga`) that **strips the M-extension entirely** — removing the multiplier, divider, their reservation stations, and the corresponding decode and dispatch entries. The resulting core is plain RV32I, has no DesignWare references, and is therefore eligible for Vivado synthesis:

```bash
$ grep DW_ riscv-cpu/sim/vcs/compile.log
$       # ← zero DesignWare references in VCS elaboration
```

The strip removed approximately 735 net lines of code across 12 files:

- `pkg/types.sv` (FU and RS type definitions cleaned of `FU_MUL` / `FU_DIV`)
- Four files under `hdl/core/` (decode, rename, dispatch, top-level CPU)
- `hdl/execution/prf.sv` (physical register file ports)
- `bin/get_options.py` and `options.json` (toolchain target changed from `rv32im` to `rv32i_zicsr`)
- Deleted: `hdl/execution/{mul,div,mul_rs,div_rs}.sv`

The CDB arbiter priority chain collapsed from `DIV > mul_buf > MUL > trade_buf > TRADE > pkt_tx_buf > PKT_TX` to simply `trade_buf > TRADE > pkt_tx_buf > PKT_TX`. The shared `cdb_mul_div` signal name was preserved to minimize diff noise; it now carries only `fetch_trade` and `pkt_tx` writebacks.

**All custom instructions (`fetch_trade`, `pkt_w`, `pkt_s`, `pkt_st`) were preserved unchanged.** The M-extension was load-bearing for exactly one benchmark (`itch_*_mixed.c`); the rest of the regression set is RV32I-clean.

We re-ran the full benchmark suite against the stripped branch and verified every single measurement is identical to the unstripped baseline, to the cycle:

| Benchmark | Cycles, stripped branch | Cycles, baseline | Match |
|---|---|---|---|
| `itch_software` | 234 | 234 | ✓ |
| `itch_mmio` | 105 | 105 | ✓ |
| `itch_custom` | 59 (IPC 0.237288) | 59 (IPC 0.237288) | ✓ |
| `itch_stream` (latency.csv) | byte-identical | byte-identical | ✓ |
| `itch_send_packet` | 64-byte capture clean | clean | ✓ |
| `itch_send_overlap` | writes=128, emits=128, overlap=16 | identical | ✓ |
| `itch_tick_to_trade` | accepted=50, p50=79 | identical | ✓ |
| `itch_tick_to_trade_sweep` | drain scales linearly | identical | ✓ |
| `itch_two_protocol` | ARP=1, OUCH=49, UNKNOWN=0 | identical | ✓ |
| `itch_max_throughput` | 29.14 cycles/packet | identical | ✓ |

The core is now in the state where it could be dropped into a Vivado project: it has no proprietary IP dependencies, the ISA target is the synthesizable subset, and the custom instructions are intact. Producing an actual bitstream containing the stripped core requires the additional integration plumbing described in §14.3 (top-level wrapper around the core + memories, BRAM mapping for instruction and data memory, clock generation, AXI-Lite slave wiring into the OpenNIC Box0 region) — that integration is the natural next milestone but was not completed within the project deadline.

---

## 7. FPGA Side: OpenNIC Packet Parser

This section describes the hardware half of the project — a Verilog packet-parser plugin synthesized into the OpenNIC framework and running on the U55C accelerator card in `hft03`.

### 7.0 Why OpenNIC, and how it fits the project

**The framework.** OpenNIC ([github.com/Xilinx/open-nic](https://github.com/Xilinx/open-nic)) is a Xilinx-maintained open-source FPGA network-interface framework. It packages, in a single shell bitstream, every piece of plumbing that a programmable 100-gigabit NIC needs:

- The Xilinx UltraScale+ Integrated 100G Ethernet Subsystem (CMAC IP) wired to the QSFP transceivers
- PCIe Gen3/4 host attachment via the QDMA subsystem
- AXI-Stream packet adapters between the CMAC and the host DMA path
- Clock generation, reset distribution, and synchronous bring-up sequencing for the two user-logic clock domains (250 MHz and 322 MHz)
- A BAR2 address map that exposes both the framework's own status registers and any user-added plugin registers to host software through memory-mapped PCIe

Building any one of these blocks from scratch is itself a multi-semester effort — the CMAC IP alone is a licensed Xilinx block with non-trivial bring-up complexity, and the QDMA/PCIe stack involves a dozen interrelated IPs configured through carefully-ordered TCL scripts. OpenNIC's value is the *shell*: it gives us two reserved Box regions (250 MHz at BAR2 `0x100000–0x1FFFFF` and 322 MHz at `0x200000–0x2FFFFF`) into which custom logic drops without having to rebuild the NIC infrastructure underneath.

#### Milestones, in chronological order

The OpenNIC half of the project advanced through four discrete strides, each of which unblocked the next:

**1. Getting OpenNIC built and flashed on a U55C at all.** Last year in IE421, our team attempted to build and program OpenNIC onto the FPGA and was unsuccessful. Our first major stride was getting Vivado configured with the correct board files, the CMAC IP license obtained, `program_fpga.sh` and `setup_device.sh` exercised against `hft03`'s PCIe bridge, the `onic` kernel module loaded, and a netdev (`ens2`) appearing in `ip link`. This stride alone took multiple weeks and required coordination with course staff on sudoers configuration, license-server access, and PCIe bridge enable bits. **End state: a stock OpenNIC bitstream programmed onto `hft03`'s U55C, the host enumerating the device, and a 100-gigabit Ethernet interface visible to the operating system.**

**2. Integrating the custom parser plugin into Box1.** Once the framework was demonstrably working, we wrote and integrated `plugin/p2p/packetparser_322mhz_simple.sv` — a Tier-3-capable ITCH/MoldUDP64 parser that snoops the CMAC RX AXI-Stream, decodes the Ethernet / IPv4 / UDP / MoldUDP64 / ITCH layered protocol stack in hardware, and exposes the decoded fields as named module outputs.

**3. Adding the AXI-Lite register interface.** To make the parsed fields readable from host software, we added the 28-register AXI-Lite block in `plugin/p2p/p2p_322mhz.sv` (later extended to 33 registers as the diagnostic counters in §13.4 were added during bring-up) and wired it into OpenNIC's BAR2 address space at offset `0x200000`. This is the interface between hardware and software: a single 32-bit memory-mapped load from the host returns the most recently parsed `msg_type`, `stock_locate`, `price`, `share_amt`, `stock_sym`, or any other field — with no kernel-driver round-trip, no DMA descriptor setup, no syscall. The host-side tools `bar_read` and `read_parser_regs.py` wrap this interface so any group member with the sudoers permission described in §4 can inspect parser state from a shell.

**4. Flashing the integrated bitstream and verifying end-to-end correctness.** The final stride was producing a working bitstream containing the parser and the AXI-Lite interface together, programming it onto the U55C, configuring the network interface with CMAC PCS internal loopback, and running the end-to-end demo described in §10. In that demo, `send_itch.py` emits real MoldUDP64-wrapped ITCH Add Order packets from the kernel through `ens2`, the CMAC delivers them to the parser via loopback, the parser decodes every protocol layer, and the host reads back every parsed field through BAR2. Verifying that this entire chain produced *exactly* the field values the sender emitted — `msg_type='A'`, `buy_sell='B'`, `stock_sym="AAPL"`, `price=9989684`, `share_amt=1004`, `stock_locate=0x1234`, `ref_num=0x0123ABCD000186A5` — is what closes the loop and what makes the parser a hardware artifact rather than a simulation artifact.

The remainder of this section documents the technical structure that supports those four milestones.

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

The helper defaults to `hft03`'s U55C BDF (`0000:83:00.0`) but honors the `OPENNIC_BDF` environment variable for other hosts. Use `sudo -E` when overriding the BDF so the environment variable survives the sudo invocation:

```bash
OPENNIC_BDF=0000:af:00.0 sudo -E bar_read 0x200000
```

The 4-byte read size, default BDF, and per-call bounds-check against the BAR size reported by `fstat` are documented in the script's docstring at `open-nic-shell/script/bar_read.py`.

**`bar_write.py`** — privileged 32-bit word write to BAR2.

```bash
sudo bar_write 0x8090 0x00002222    # write GT_LOOPBACK_REG_0 (CMAC IP)
```

Same portability semantics as `bar_read.py`: defaults to `hft03`'s BDF, honors `OPENNIC_BDF`, requires `sudo -E` when overriding. Added during bring-up; useful for poking CMAC IP registers without rebuilding.

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

### 9.3 Run the programming flow

The wrapper installed in §5.1 (`/usr/local/bin/program_open_nic_fpga`) calls the repo's `script/program_fpga.sh` internally. Invoke it through sudo so the scoped NOPASSWD rule (§4.1) takes effect:

```bash
# from anywhere on hft03 — paths to the bitstream are relative to wherever you cd'd to
export EXTENDED_DEVICE_BDF1=0000:83:00.0
sudo -E /usr/local/bin/program_open_nic_fpga \
    /absolute/or/relative/path/to/open_nic_shell.bit \
    au55c
```

`-E` is required so the exported `EXTENDED_DEVICE_BDF1` survives the sudo invocation. The expected bitstream is the file produced by the Vivado build in §8.1:

```
${PROJECT_ROOT}/open-nic-shell/build/au55c_<tag>/open_nic_shell/open_nic_shell.runs/impl_1/open_nic_shell.bit
```

The wrapped script:

1. Disables `SERR#` and `ERR_FATAL` on the upstream bridge (`setpci -s 0000:80:02.0 COMMAND=0000:0100`, `CAP_EXP+8.w=0000:0004`).
2. Launches the Vivado hardware manager in interactive mode, prompts you to confirm programming, and waits for the bitstream to load.
3. After you press **`c`** to confirm completion, removes the PCIe device, rescans the upstream bridge, and re-enables memory space access (`setpci -s 0000:83:00.0 COMMAND=0x02`).

### 9.4 Load the `onic` kernel driver

The `onic` driver is built from a separate Xilinx repository (`open-nic-driver`) and installed into the runtime path during initial lab setup. On `hft03` the resulting `onic.ko` is **not** under `/lib/modules`, so `modprobe` will not find it — `insmod` against the absolute path is required.

```bash
# Discover where onic.ko lives on this host:
sudo find / -name onic.ko 2>/dev/null

# Expected (on hft03): a single hit similar to one of:
#   /opt/onic/onic.ko
#   /usr/local/lib/onic/onic.ko
#   /home/<lab-shared-account>/open-nic-driver/onic.ko

# Load it using the path you found:
sudo insmod <path-from-above>

# Verify:
lsmod | grep onic                     # expect:  onic  135168  0
ip -br link | grep ens2               # expect:  ens2  UP|DOWN ...
```

If `find` returns multiple hits, prefer the one under `/opt/` or `/usr/local/` over any user-home location. Record the verified path on your host and use it consistently across sessions.

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

## 12. Engineering Notes and Bring-Up Debug Narrative

This section captures the non-obvious engineering decisions and the debug narrative behind the FPGA bring-up. Documenting these is part of the deliverable both because they were the hardest single-issue bugs to track down and because the diagnostic methodology used to find them is reusable.

### 12.1 Why PCS loopback (not PMA)

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

### 12.2 The pm_tick fix

The CMAC IP's stat counter snapshot is gated by `pm_tick`, which in stock OpenNIC is hardwired to `1'b0`. With `pm_tick` never asserting, all stat counters readable via AXI-Lite return their power-on values regardless of how many packets actually passed through.

For runtime instrumentation we replaced the hardwired tie-off with a free-running divider:

```verilog
reg [15:0] pm_tick_div;
always @(posedge cmac_clk) pm_tick_div <= pm_tick_div + 1'b1;
assign pm_tick = &pm_tick_div;     // pulses once every 2^16 cmac_clk cycles ≈ 204 µs
```

This pulses `pm_tick` well below the IP's required sub-millisecond cadence and above its minimum 4-cycle pulse spacing.

### 12.3 The byte-ordering bug

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

### 12.4 Diagnostic counters as a methodology

The byte-ordering bug would have been substantially harder to find without the seven diagnostic registers added during bring-up. The reusable principle: when a downstream counter (`REG_PARSED_MSG_COUNT`) refuses to move and the upstream counter (`REG_PACKET_COUNT`) is moving correctly, add intermediate counters that progressively localize where in the FSM the signal disappears. Specifically:

- `BEAT_COUNT` — total valid beats (independent of FSM state)
- `BEAT0_COUNT` — entries into the header-parse branch
- `BEAT1_COUNT` — entries into the payload-parse branch
- `LAST_MSG_TYPE_SEEN` — the actual byte at the position the parser reads from
- `LAST_TKEEP_ON_TLAST` — the per-byte validity mask on packet-end

Combined, these counters answered "did the FSM enter beat 1?" (yes, from `BEAT1_COUNT` rising) and "what byte is at the parser's read position?" (`0x00`, from `LAST_MSG_TYPE_SEEN`). Those two facts together identified byte-ordering as the cause without requiring an internal logic analyzer (ILA) or a rebuild.

### 12.5 Why the parser sees CMAC RX directly (not via the adapter)

The packet adapter in OpenNIC's C2H path can be configured to prepend a per-packet metadata header (16–22 bytes) before handing packets up to QDMA. If the parser tapped this post-adapter path, every parsed offset would be shifted by the metadata length and would need accounting.

The parser instead taps `s_axis_cmac_rx_*` *before* the adapter, so it sees raw Ethernet frames as the CMAC presents them. This is intentional and architecturally consistent with the "tap, don't transform" design philosophy.

---

## 13. Known Limitations and Future Work

### 13.1 Loopback-only end-to-end testing

The FPGA parser has only been exercised under PCS internal loopback. We have not connected the U55C to an external 100 Gigabit Ethernet source. The PCS-loopback path exercises the full CMAC RX datapath, AXI-Stream presentation, and parser FSM exactly as a real link partner would, but cannot validate link-layer behaviors that depend on remote-end alignment (auto-negotiation, FEC convergence under bit errors, etc.).

### 13.2 Tier-3 multi-message coverage

The simple parser handles up to 2 ITCH messages per MoldUDP64 packet (Tier 3). Production NASDAQ feeds can pack more. Extending to N-message packets requires generalizing the cross-beat completion FSM in `packetparser_322mhz_simple.sv`.

### 13.3 CPU on FPGA — synthesizability achieved, integration deferred

All cycle-accurate measurements in §6 were taken in VCS simulation on EWS. The original RV32IM core could not be synthesized in Vivado because of its Synopsys DesignWare dependency. We addressed the synthesizability blocker directly: as described in §6.10, the `roshnim/cpu-fpga` branch strips the M-extension, removes all DesignWare references, and verifies that the full benchmark regression set still passes with cycle-for-cycle identical results to the unstripped baseline. VCS elaboration of that branch produces a DesignWare-free compile log, and the toolchain target is set to `rv32i_zicsr`.

What remains for an actual FPGA bitstream containing the stripped core is **integration work, not core work**: writing a top-level synthesizable wrapper around the core, mapping the instruction and data memories to Xilinx BRAM primitives (the project's `xpm_memory_sdpram` instances already in use for `fetch_trade` and `pkt_tx` are FPGA-friendly), generating a CPU clock from a Vivado MMCM, and wiring the core's AXI-Lite interface into OpenNIC's Box0 region so the host can probe the core via PCIe BAR2. None of these steps requires further HDL modification of the core. Producing the integrated bitstream was not completed within the project's two-day final push but the prerequisite — getting the core into a synthesizable state without losing any custom-instruction functionality — is done.

### 13.4 Closed-system integration

The two halves of the project — parser and CPU — share a logical model (the parser produces what the CPU reads via `fetch_trade`) but are not physically wired together. A fully integrated demonstration would place a stripped-down RV32I core directly into OpenNIC's Box0 region, wire the parser's output stream to the CPU's `fetch_trade` BRAM, and run the full closed loop on a single FPGA. The stub plugin scaffolding for Box0 is in place (`plugin/cpu/cpu_stub.sv`); it currently returns a static "RISC" magic value via BAR2 and is a placeholder for the real core.

### 13.5 No real-exchange feed

We exercised the parser against synthetic MoldUDP64 packets emitted by `send_itch.py`, not against a real exchange feed. The synthetic packets follow the NASDAQ ITCH spec layout exactly, but a real-world deployment would need additional handling for retransmission protocols (MoldUDP64 gap-fill, etc.) that are out of scope here.

---

## 14. References

1. **NASDAQ TotalView-ITCH 5.0 Specification.** Defines the binary message layout for `0x41` Add Order, `0x69` Add Order with MPID, `0x68` Stock Trading Action, and other ITCH message types. Used as the authoritative source for parser field offsets.

2. **NASDAQ MoldUDP64 Specification.** Defines the UDP-encapsulated framing of ITCH messages: 10-byte session id, 8-byte sequence number, 2-byte message count, then per-message {2-byte length, payload} pairs.

3. **Xilinx PG203 — UltraScale+ Devices Integrated 100G Ethernet Subsystem Product Guide.** Documents the CMAC AXI-Stream interface convention (byte 0 at `tdata[7:0]`), the loopback mode encodings, the stat-counter pm_tick requirement, and the IP register map.

4. **Xilinx OpenNIC framework.** [github.com/Xilinx/open-nic](https://github.com/Xilinx/open-nic), [github.com/Xilinx/open-nic-shell](https://github.com/Xilinx/open-nic-shell), [github.com/Xilinx/open-nic-driver](https://github.com/Xilinx/open-nic-driver). Our forks live in this project's `open-nic-shell/` submodule.

5. **NASDAQ OUCH 5.0 Specification.** Order-entry protocol used as the message format for the OUCH-shaped frames in the CPU side's two-protocol demonstration.

6. **RISC-V Unprivileged ISA Specification, v2.2.** Defines the `custom-0` through `custom-3` opcode space (`0x0B`, `0x2B`, `0x5B`, `0x7B`) used for `fetch_trade` (custom-1) and `pkt_w` / `pkt_s` / `pkt_st` (custom-2).

---

*End of report.*
