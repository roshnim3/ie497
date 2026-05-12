#!/bin/bash

# Out-Of-Order CPU Complete Build and Test Script
# Note: We don't use 'set -e' globally to allow individual test failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print process ID for easy termination
echo -e "${BLUE}[INFO]${NC} Script PID: $$ (use 'kill $$' to stop)"

# Function to print colored status messages
print_status() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get script directory to ensure relative paths work
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Run power analysis and report PD^4 for the most recent simulation.
# Also populates global POWER_MW, DELAY_MS, and PD4 for table printing.
run_power_pd4() {
    local label="$1"

    if (cd "$SCRIPT_DIR/synth" && make power_vcs >/dev/null 2>&1); then
        local metrics
        metrics=$(compute_power_delay_pd4) || {
            print_warning "PD^4 calculation skipped for ${label:-latest run}"
            return 1
        }

        # Populate globals used by the summary table
        read -r POWER_MW DELAY_MS PD4 <<<"$metrics"

        printf "Metrics%s: Power=%s mW, Delay=%s ms, PD^4=%s\n" \
            "${label:+ ($label)}" "$POWER_MW" "$DELAY_MS" "$PD4"
        return 0
    else
        print_warning "power_vcs failed for ${label:-latest run}"
        return 1
    fi
}

# Compute power (mW), delay (ms), and PD^4 = power * delay^4 using power2.rpt and simulation log
compute_power_delay_pd4() {
    local power_rpt="$SCRIPT_DIR/synth/reports/power2.rpt"
    local sim_log="$SCRIPT_DIR/sim/vcs/simulation.log"

    if [[ ! -f "$power_rpt" ]]; then
        print_warning "PD^4: Missing $power_rpt (run synthesis/power first)"
        return 1
    fi
    if [[ ! -f "$sim_log" ]]; then
        print_warning "PD^4: Missing $sim_log (run a simulation that produces Monitor time)"
        return 1
    fi

    local power_mw
    power_mw=$(cd "$SCRIPT_DIR/synth" && ./get_power.py 2>/dev/null) || return 1

    # Prefer Segment Time, fall back to Total Time; values are in ps (timeunit 1ps in top_tb)
    local time_ps
    time_ps=$(grep -oE "Monitor: (Segment|Total) Time: +([0-9]+)" "$sim_log" \
        | awk '{print $NF}' \
        | tail -1)

    if [[ -z "$time_ps" ]]; then
        print_warning "PD^4: Could not find Segment/Total Time in simulation log"
        return 1
    fi

    local metrics_output
    metrics_output=$(python3 - "$power_mw" "$time_ps" <<'PY'
import sys
power_mw = float(sys.argv[1])
time_ps = float(sys.argv[2])
delay_ms = time_ps / 1e9  # convert ps -> ms (timeunit 1ps)
pd4 = power_mw * (delay_ms ** 4)
print(f"{power_mw:.2f} {delay_ms:.3f} {pd4:.2f}")
PY
) || return 1

    # Return three space-separated values: power_mw delay_ms pd4
    echo "$metrics_output"
}

# Print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  lint       Run lint checks only"
    echo "  sim        Run simulation tests only"
    echo "  synth      Run synthesis only"
    echo "  all        Run all stages (default)"
    echo "  help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Run all stages"
    echo "  $0 lint         # Run only lint"
    echo "  $0 sim synth    # Run simulation and synthesis"
    echo "  $0 lint sim     # Run lint and simulation"
}

# Parse command line arguments
RUN_LINT=false
RUN_SIM=false
RUN_SYNTH=false

# If no arguments, run all
if [[ $# -eq 0 ]]; then
    RUN_LINT=true
    RUN_SIM=true
    RUN_SYNTH=true
else
    # Parse each argument
    for arg in "$@"; do
        case "$arg" in
            lint)
                RUN_LINT=true
                ;;
            sim)
                RUN_SIM=true
                ;;
            synth)
                RUN_SYNTH=true
                ;;
            all)
                RUN_LINT=true
                RUN_SIM=true
                RUN_SYNTH=true
                ;;
            help|--help|-h)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $arg"
                print_usage
                exit 1
                ;;
        esac
    done
fi

echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}  Out-Of-Order CPU Build & Test     ${NC}"
echo -e "${BLUE}====================================${NC}"

# Show what will be run
STAGES=""
[[ $RUN_LINT == true ]] && STAGES="${STAGES}Lint "
[[ $RUN_SIM == true ]] && STAGES="${STAGES}Simulation "
[[ $RUN_SYNTH == true ]] && STAGES="${STAGES}Synthesis "
print_status "Running stages: ${STAGES}"
echo ""

# Step 1: Lint check
if [[ $RUN_LINT == true ]]; then
    print_status "Running lint checks..."
    cd lint
    if make lint; then
        print_success "Lint checks passed"
    else
        print_error "Lint checks failed"
        print_warning "Continuing with remaining stages despite lint failures..."
    fi
    cd "$SCRIPT_DIR"
fi

# Step 2: Run simulation tests
test_count=0
pass_count=0

if [[ $RUN_SIM == true ]]; then
    print_status "Running simulation tests..."
    cd sim

    # Check if testlogs directory exists, create if needed, and clean it
    if [[ -d "../testlogs" ]]; then
        print_status "Cleaning testlogs directory..."
        rm -f ../testlogs/test_*.log
        LOGS_DIR="../testlogs"
    else
        print_status "Creating testlogs directory..."
        mkdir -p ../testlogs
        LOGS_DIR="../testlogs"
    fi

    # Run selected benchmark ELF tests
    print_status "Running selected benchmark ELF tests..."
    BENCHMARKS=(coremark_im.elf aes_sha.elf compression.elf fft.elf mergesort.elf)

    # Collect rows to print at the end
    declare -a table_rows=()

    for bench in "${BENCHMARKS[@]}"; do
        # Resolve path (coremark_im.elf lives in ../testcode, others in cp3_release_benches/im)
        bench_path="../testcode/cp3_release_benches/im/$bench"
        if [[ ! -f "$bench_path" ]]; then
            bench_path="../testcode/$bench"
        fi
        if [[ ! -f "$bench_path" ]]; then
            print_warning "Skipping $bench (file not found)"
            continue
        fi

        test_name=$(basename "$bench_path")
        print_status "Testing: $test_name"

        # Reset metrics for this run
        POWER_MW="N/A"
        DELAY_MS="N/A"
        PD4="N/A"

        # Clean and run test, capturing both success and failure
        log_file="${LOGS_DIR}/test_${test_name}.log"
        make run_vcs_top_tb PROG="$bench_path" >"$log_file" 2>&1
        test_result=$?

        # Extract IPC from simulation log
        ipc="N/A"
        if [[ -f "vcs/simulation.log" ]]; then
            ipc=$(grep -oE 'Monitor: (Total|Segment) IPC: +?([0-9]+?\.[0-9]+?)' vcs/simulation.log 2>/dev/null \
                | tail -1 \
                | grep -oE '[0-9]+\.[0-9]+' || echo "N/A")
        fi

        if [[ $test_result -eq 0 ]]; then
            print_success "PASS: $test_name (IPC: $ipc)"
            # Run power analysis and populate POWER_MW / DELAY_MS / PD4
            run_power_pd4 "$test_name" || true

            # Delete log file for passed tests to keep directory clean
            rm -f "$log_file"
            ((pass_count++))
        else
            print_error "FAIL: $test_name (IPC: $ipc) (see $(basename "$log_file"))"
        fi
        ((test_count++))

        # Save raw values for table to print later
        table_rows+=("$bench|$ipc|$POWER_MW|$DELAY_MS|$PD4")
    done

    # Print summary table at the end
    echo ""
    printf "%-16s %-10s %-12s %-12s %-12s\n" \
        "Benchmark" "IPC" "Power (mW)" "Delay (ms)" "PD^4"
    printf "%-16s %-10s %-12s %-12s %-12s\n" \
        "---------" "--------" "----------" "----------" "----------"

    for row in "${table_rows[@]}"; do
        IFS="|" read -r bench ipc power delay pd4 <<<"$row"
        printf "%-16s %-10s %-12s %-12s %-12s\n" \
            "$bench" "$ipc" "$power" "$delay" "$pd4"
    done

    echo -e "\n${BLUE}Test Summary:${NC} $pass_count/$test_count tests passed"

    if [[ $pass_count -ne $test_count ]]; then
        failed_count=$((test_count - pass_count))
        if [[ "$LOGS_DIR" == "../testlogs" ]]; then
            print_warning "$failed_count test(s) failed. Check testlogs/ directory for failure details."
        else
            print_warning "$failed_count test(s) failed. Check test_*.log files for failure details."
        fi
    elif [[ $test_count -gt 0 ]]; then
        print_status "All tests passed - removing testlogs directory (no failures to log)"
        # Remove the entire testlogs directory since all tests passed
        if [[ "$LOGS_DIR" == "../testlogs" ]] && [[ -d "../testlogs" ]]; then
            rm -rf ../testlogs
        fi
    fi

    cd "$SCRIPT_DIR"
fi

# Step 3: Synthesis
synth_result=0

if [[ $RUN_SYNTH == true ]]; then
    cd synth

    make synth >/dev/null 2>&1
    synth_result=$?

    if [[ $synth_result -eq 0 ]]; then
        # Show timing and area results if available
        if [[ -f "reports/timing.rpt" ]]; then
            slack=$(grep -i "slack" reports/timing.rpt | head -1 2>/dev/null || echo "Slack: Not found")
            print_status "Timing: $slack"
        fi

        if [[ -f "reports/area.rpt" ]]; then
            area=$(grep -i "total" reports/area.rpt | head -1 2>/dev/null || echo "Area: Not found")
            print_status "Area: $area"
        fi
    else
        print_error "Synthesis failed (see synthesis.log)"
        print_warning "Build completed with synthesis errors"
    fi

    cd "$SCRIPT_DIR"
fi

# Final summary
echo -e "\n${BLUE}================================${NC}"

# Determine overall status based on what was actually run
overall_success=true

# Check simulation results if sim was run
if [[ $RUN_SIM == true ]] && [[ $test_count -gt 0 ]]; then
    if [[ $pass_count -ne $test_count ]]; then
        overall_success=false
        print_warning "Simulation: $pass_count/$test_count tests passed"
    else
        print_success "Simulation: All $test_count tests passed"
    fi
fi

# Check synthesis results if synth was run
if [[ $RUN_SYNTH == true ]]; then
    if [[ $synth_result -eq 0 ]]; then
        print_success "Synthesis: Completed successfully"
    else
        overall_success=false
        print_error "Synthesis: Failed"
    fi
fi

# Overall summary message
if [[ $overall_success == true ]]; then
    echo -e "${GREEN}  All requested stages completed successfully!${NC}"
else
    echo -e "${YELLOW}  Some stages had issues - check details above${NC}"
fi
echo -e "${BLUE}================================${NC}"

# Exit with appropriate code
if [[ $overall_success == true ]]; then
    exit 0
else
    exit 1
fi
