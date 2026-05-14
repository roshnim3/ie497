#!/bin/bash
# Sweep ITER across the 3 paths and capture cycles. Emits a CSV.
#
# Usage:
#   cd ~/SP26/ie497/riscv-cpu && source setup_env.sh
#   testcode/sim_b/run_scaling.sh
#
# Output: testcode/sim_b/scaling_results.csv

set -e
set -o pipefail

cd "$(dirname "$0")"
SIM_B_DIR="$(pwd)"
REPO_ROOT="$(cd ../.. && pwd)"
OUT_CSV="$SIM_B_DIR/scaling_results.csv"
CLOCK_PS=1850

echo "path,iter,segment_ps,cycles,ipc,commits" > "$OUT_CSV"

for iter in 1 10 100 1000; do
    for prog in itch_swparse_loop itch_mmio_loop itch_custom_loop; do
        # Patch ITER in the source file.
        sed -i "s/^#define ITER .*/#define ITER $iter/" "$SIM_B_DIR/$prog.c"

        # Compile + run.
        cd "$REPO_ROOT/sim"
        make EXTRA_VCS_FLAGS="+define+ECE411_NO_SPIKE_DPI" \
             run_vcs_top_tb \
             PROG="$SIM_B_DIR/$prog.c" 2>&1 \
            | awk -v path="$prog" -v iter="$iter" -v clk="$CLOCK_PS" '
                /Segment Time/      { seg_ps = $NF }
                /Segment IPC/       { ipc = $NF }
                /Total Commits/     { commits = $NF }
                END {
                    cycles = seg_ps / clk
                    printf "%s,%d,%d,%.0f,%s,%d\n", path, iter, seg_ps, cycles, ipc, commits
                }' \
            >> "$OUT_CSV"
        cd "$SIM_B_DIR"
    done
done

# Reset ITER in each file to 100 so the source files don't carry sweep state.
for prog in itch_swparse_loop itch_mmio_loop itch_custom_loop; do
    sed -i "s/^#define ITER .*/#define ITER 100/" "$SIM_B_DIR/$prog.c"
done

echo ""
echo "=== Results in $OUT_CSV ==="
column -t -s, "$OUT_CSV"
