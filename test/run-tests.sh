#!/bin/bash
# run-tests.sh — Multi-kernel test orchestrator
#
# Entry point for the quotatool test suite. Reads kernels.conf, boots
# each kernel in a VM, runs the full test suite inside it, collects
# results.
#
# Usage:
#   ./run-tests.sh                    # run all kernels
#   ./run-tests.sh --tier 1           # run tier 1 only
#   ./run-tests.sh --kernel alma8     # run one kernel
#   ./run-tests.sh --host-only        # run on host kernel only (fast)
#   ./run-tests.sh --timeout 600      # per-kernel timeout (default: 300)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/kernels/kernels.conf"
RESULTS_DIR="$SCRIPT_DIR/results"

# Source boot layer
source "$SCRIPT_DIR/lib/boot.sh"

# Colors (if terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Find the vmlinuz path for an extracted kernel.
find_vmlinuz() {
    local name="$1"
    local dir="$SCRIPT_DIR/kernels/$name/extracted"
    ls "$dir"/boot/vmlinu* 2>/dev/null | grep -v '\.gz$' | head -1 && return
    find "$dir/lib/modules" -maxdepth 2 -name "vmlinuz" 2>/dev/null | head -1 && return
    find "$dir/usr/lib/modules" -maxdepth 2 -name "vmlinuz" 2>/dev/null | head -1
}

# Check if a kernel has 9p filesystem support (module or built-in).
has_9p() {
    local name="$1"
    local dir="$SCRIPT_DIR/kernels/$name/extracted"
    # Check for 9p.ko module (any compression: .ko, .ko.xz, .ko.zst)
    find "$dir" -name "9p.ko" -o -name "9p.ko.*" 2>/dev/null | grep -q . && return 0
    # Check modules.builtin for 9p filesystem (not 9pnet)
    local builtin
    builtin=$(find "$dir" -name "modules.builtin" 2>/dev/null | head -1)
    [[ -n "$builtin" ]] && grep -q '/9p\.ko' "$builtin" 2>/dev/null && return 0
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
Usage: run-tests.sh [OPTIONS]

Run the quotatool test suite across multiple kernels.

Options:
  --tier N        Only run kernels of tier N (1, 2, or 3)
  --kernel NAME   Only run the named kernel
  --host-only     Run tests on the host kernel only (no VMs, fast)
  --timeout SECS  Per-kernel timeout in seconds (default: 300)
  -v, --verbose   Verbose boot output
  -h, --help      Show this help
EOF
}

OPT_TIER=""
OPT_KERNEL=""
OPT_HOST_ONLY=0
OPT_TIMEOUT="300"
OPT_VERBOSE="0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)      OPT_TIER="$2"; shift 2 ;;
        --kernel)    OPT_KERNEL="$2"; shift 2 ;;
        --host-only) OPT_HOST_ONLY=1; shift ;;
        --timeout)   OPT_TIMEOUT="$2"; shift 2 ;;
        -v|--verbose) OPT_VERBOSE="1"; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Ensure quotatool is built
QUOTATOOL="$SCRIPT_DIR/../src/quotatool"
if [[ ! -x "$QUOTATOOL" ]]; then
    echo -e "${YELLOW}Building quotatool...${NC}"
    make -C "$SCRIPT_DIR/.." -j"$(nproc)" >/dev/null 2>&1 \
        || { echo -e "${RED}Build failed${NC}"; exit 1; }
fi

# Set boot layer options
export BOOT_TIMEOUT="$OPT_TIMEOUT"
export BOOT_VERBOSE="$OPT_VERBOSE"

# Create results directory
mkdir -p "$RESULTS_DIR"

# The command to run inside each VM
GUEST_CMD="$SCRIPT_DIR/guest-run-all.sh"

# ---------------------------------------------------------------------------
# Host-only mode
# ---------------------------------------------------------------------------

if [[ $OPT_HOST_ONLY -eq 1 ]]; then
    echo -e "${BOLD}Running tests on host kernel $(uname -r)${NC}"
    echo ""
    boot_host_kernel "$GUEST_CMD"
    exit $?
fi

# ---------------------------------------------------------------------------
# Multi-kernel mode
# ---------------------------------------------------------------------------

if [[ ! -f "$CONF" ]]; then
    echo "ERROR: kernels.conf not found at $CONF" >&2
    echo "Run: test/kernels/download.sh" >&2
    exit 1
fi

# Read kernels.conf
mapfile -t entries < <(grep -v '^\s*#' "$CONF" | grep -v '^\s*$')

passed=0
failed=0
skipped=0
declare -a failed_names=()
declare -a skipped_names=()

echo -e "${BOLD}quotatool multi-kernel test suite${NC}"
echo -e "Kernels: ${#entries[@]} in matrix"
echo -e "Tests: $(ls "$SCRIPT_DIR/tests"/t-*.sh 2>/dev/null | wc -l) test scripts × 2 filesystems"
echo ""

for entry in "${entries[@]}"; do
    IFS='|' read -r name version boot tier source <<< "$entry"

    # Trim whitespace
    name=$(echo "$name" | xargs)
    version=$(echo "$version" | xargs)
    boot=$(echo "$boot" | xargs)
    tier=$(echo "$tier" | xargs)
    source=$(echo "$source" | xargs)
    [[ -z "$name" ]] && continue

    # Filter by tier
    if [[ -n "$OPT_TIER" && "$tier" != "$OPT_TIER" ]]; then
        continue
    fi

    # Filter by kernel name
    if [[ -n "$OPT_KERNEL" && "$name" != "$OPT_KERNEL" ]]; then
        continue
    fi

    source_type="${source%%:*}"

    # Skip unavailable
    if [[ "$source_type" == "unavailable" ]]; then
        skipped=$((skipped + 1))
        skipped_names+=("$name(unavail)")
        continue
    fi

    # Skip kernels without 9p (Q7)
    if ! has_9p "$name"; then
        printf "%-20s %-8s %-8s " "$name" "$version" "$boot"
        echo -e "${YELLOW}SKIP${NC} (no 9p module — Q7)"
        skipped=$((skipped + 1))
        skipped_names+=("$name(no-9p)")
        continue
    fi

    # Find vmlinuz
    vmlinuz=$(find_vmlinuz "$name")
    if [[ -z "$vmlinuz" ]]; then
        printf "%-20s %-8s %-8s " "$name" "$version" "$boot"
        echo -e "${RED}FAIL${NC} vmlinuz not found"
        failed=$((failed + 1))
        failed_names+=("$name")
        continue
    fi

    # Run test suite on this kernel
    printf "%-20s %-8s %-8s " "$name" "$version" "$boot"

    result_file="$RESULTS_DIR/${name}.log"
    rc=0
    BOOT_METHOD="$boot" boot_kernel "$vmlinuz" "$GUEST_CMD" > "$result_file" 2>&1 || rc=$?

    if [[ $rc -eq 0 ]]; then
        # Extract pass/fail counts from guest output
        summary=$(grep -E '^Results:' "$result_file" | tail -1)
        echo -e "${GREEN}PASS${NC} $summary"
        passed=$((passed + 1))
    elif [[ $rc -eq 124 ]]; then
        echo -e "${RED}TIMEOUT${NC} (${OPT_TIMEOUT}s)"
        failed=$((failed + 1))
        failed_names+=("$name")
    else
        # Extract failure details
        failures=$(grep -E '^  FAIL:' "$result_file" | head -5)
        echo -e "${RED}FAIL${NC} (exit $rc)"
        [[ -n "$failures" ]] && echo "$failures" | sed 's/^/    /'
        failed=$((failed + 1))
        failed_names+=("$name")
    fi
done

echo ""
echo "========================================================================"
echo -e "Results: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}, ${YELLOW}${skipped} skipped${NC}"
[[ ${#failed_names[@]} -gt 0 ]] && echo -e "Failed: ${RED}${failed_names[*]}${NC}"
[[ ${#skipped_names[@]} -gt 0 ]] && echo -e "Skipped: ${YELLOW}${skipped_names[*]}${NC}"
echo ""
echo "Logs: $RESULTS_DIR/"

[[ $failed -gt 0 ]] && exit 1
exit 0
