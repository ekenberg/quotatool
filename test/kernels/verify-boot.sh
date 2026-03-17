#!/bin/bash
# verify-boot.sh — Boot-verify all kernels in the test matrix.
#
# For each kernel in kernels.conf: boot it, run `uname -r`, verify
# the reported version matches the expected version.
#
# This catches: missing modules, bad initramfs, broken configs,
# boot method mismatches.
#
# Usage:
#   ./verify-boot.sh                  # verify all kernels
#   ./verify-boot.sh --tier 1         # verify tier 1 only
#   ./verify-boot.sh --kernel alma-8   # verify one kernel
#   ./verify-boot.sh --timeout 60     # per-kernel timeout (default: 120s)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/kernels.conf"
LIB_DIR="$SCRIPT_DIR/../lib"

# Source boot layer
# shellcheck source=../lib/boot.sh
source "$LIB_DIR/boot.sh"

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
    local dir="$SCRIPT_DIR/$name/extracted"
    ls "$dir"/boot/vmlinu* 2>/dev/null | head -1 && return
    find "$dir/lib/modules" -maxdepth 2 -name "vmlinuz" 2>/dev/null | head -1 && return
    find "$dir/usr/lib/modules" -maxdepth 2 -name "vmlinuz" 2>/dev/null | head -1
}

# Check if reported uname matches expected version (major.minor prefix).
version_matches() {
    local uname_output="$1"
    local expected="$2"
    # uname -r returns e.g. "5.4.0-216-generic" — check major.minor prefix
    [[ "$uname_output" == "$expected".* ]]
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Boot-verify all kernels in the test matrix.

Options:
  --tier N        Only verify kernels of tier N (1, 2, or 3)
  --kernel NAME   Only verify the named kernel
  --timeout SECS  Per-kernel boot timeout (default: 120)
  -v, --verbose   Verbose boot output
  -h, --help      Show this help
EOF
}

OPT_TIER=""
OPT_KERNEL=""
OPT_TIMEOUT="120"
OPT_VERBOSE="0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)    OPT_TIER="$2"; shift 2 ;;
        --kernel)  OPT_KERNEL="$2"; shift 2 ;;
        --timeout) OPT_TIMEOUT="$2"; shift 2 ;;
        -v|--verbose) OPT_VERBOSE="1"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ ! -f "$CONF" ]]; then
    echo "ERROR: kernels.conf not found at $CONF" >&2
    exit 1
fi

# Set boot layer options
export BOOT_TIMEOUT="$OPT_TIMEOUT"
export BOOT_VERBOSE="$OPT_VERBOSE"
export BOOT_MEMORY="512"   # minimal for uname check

passed=0
failed=0
skipped=0
declare -a failed_names=()

echo ""
printf "${BOLD}%-20s %-8s %-8s %-5s %-8s %s${NC}\n" \
    "KERNEL" "VERSION" "BOOT" "TIER" "STATUS" "DETAILS"
echo "------------------------------------------------------------------------"

# Read kernels.conf into array to avoid pipeline subshell
mapfile -t entries < <(grep -v '^\s*#' "$CONF" | grep -v '^\s*$')

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
        printf "%-20s %-8s %-8s %-5s " "$name" "$version" "$boot" "$tier"
        echo -e "${YELLOW}SKIP${NC}     unavailable"
        skipped=$((skipped + 1))
        continue
    fi

    # Find vmlinuz
    vmlinuz=$(find_vmlinuz "$name")
    if [[ -z "$vmlinuz" ]]; then
        printf "%-20s %-8s %-8s %-5s " "$name" "$version" "$boot" "$tier"
        echo -e "${RED}FAIL${NC}     vmlinuz not found (run download.sh first)"
        failed=$((failed + 1))
        failed_names+=("$name")
        continue
    fi

    # Boot and run uname -r
    printf "%-20s %-8s %-8s %-5s " "$name" "$version" "$boot" "$tier"

    uname_out=""
    boot_rc=0
    uname_out=$(BOOT_METHOD="$boot" boot_kernel "$vmlinuz" "uname -r" 2>/dev/null) || boot_rc=$?

    if [[ $boot_rc -ne 0 ]]; then
        echo -e "${RED}FAIL${NC}     boot failed (exit $boot_rc)"
        failed=$((failed + 1))
        failed_names+=("$name")
        continue
    fi

    # Clean up uname output (strip trailing whitespace/newlines, take last line)
    uname_out=$(echo "$uname_out" | tr -d '\r' | tail -1 | xargs)

    if version_matches "$uname_out" "$version"; then
        echo -e "${GREEN}PASS${NC}     uname=$uname_out"
        passed=$((passed + 1))
    else
        echo -e "${RED}FAIL${NC}     expected=${version}.* got=$uname_out"
        failed=$((failed + 1))
        failed_names+=("$name")
    fi
done

echo ""
echo "------------------------------------------------------------------------"
echo -e "Results: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}, ${YELLOW}${skipped} skipped${NC}"

if [[ ${#failed_names[@]} -gt 0 ]]; then
    echo -e "Failed: ${RED}${failed_names[*]}${NC}"
    exit 1
fi
