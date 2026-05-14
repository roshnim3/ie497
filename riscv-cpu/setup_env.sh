#!/bin/bash
# Non-interactive ECE411 env setup (avoids the `[[ $- == *i* ]]` gate in /class/ece411/ece411.sh).
# Source this before running ./run.sh sim or make.

module load Synopsys_x86-64/2024 2>/dev/null
module load xilinx/2025.1 2>/dev/null

export ECE411_GUI_TIMEOUT=1h
export OPENRAM=/class/ece411/OpenRAM
export FREEPDK45=/class/ece411/freepdk-45nm
export CBP2016=/class/ece411/cbp2016
export DW=/software/Synopsys-2024_x86_64/icc/W-2024.09/dw
export UVM_HOME=/software/Synopsys-2024_x86_64/vcs/W-2024.09/etc/uvm-1.2

# Vivado XPM_MEMORY sources used by the fetch_trade FU. The xilinx module
# doesn't always export XILINX_VIVADO, so pin it explicitly.
export XILINX_VIVADO=${XILINX_VIVADO:-/software/xilinx-2025.1/2025.1/Vivado}

case ":$PATH:" in
  *":/class/ece411/riscv/bin:"*) ;;
  *) export PATH="$PATH:/class/ece391/rhel8/bin:/class/ece411/riscv/bin:/class/ece411/verilator/bin:/class/ece411/cacti" ;;
esac

case ":${LD_LIBRARY_PATH:-}:" in
  *":/class/ece411/riscv/lib:"*) ;;
  *) export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:/class/ece411/riscv/lib:/class/ece411/riscv/lib64" ;;
esac
