#!/bin/bash
# run-tests.sh — Multi-kernel test orchestrator
#
# Entry point for the quotatool test suite. Reads kernels.conf, boots
# each kernel in a VM, runs the full test suite inside it, collects
# results.
#
# Usage:
#   ./run-tests.sh                    # run all kernels
#   ./run-tests.sh --jobs 4           # run 4 kernels in parallel
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

# Check if a kernel has a cached pass result from a previous run.
# Returns 0 (true) if results/<name>.log exists and shows 0 failures.
_is_cached_pass() {
    local name="$1"
    local result_file="$RESULTS_DIR/${name}.log"
    [[ -f "$result_file" ]] \
        && grep -qE '^Results:.*0 failed' "$result_file" 2>/dev/null
}

# Print result line for a completed kernel test.
# Args: $1=name $2=version $3=boot_path $4=exit_code
_print_result() {
    local name="$1" version="$2" actual_boot="$3" rc="$4"
    local result_file="$RESULTS_DIR/${name}.log"

    printf "%-20s %-8s %-12s " "$name" "$version" "$actual_boot"
    if [[ $rc -eq 0 ]]; then
        local summary
        summary=$(grep -E '^Results:' "$result_file" 2>/dev/null | tail -1 || true)
        echo -e "${GREEN}PASS${NC} $summary"
    elif [[ $rc -eq 124 || $rc -eq 137 ]]; then
        echo -e "${RED}TIMEOUT${NC} (${OPT_TIMEOUT}s)"
    else
        local failures
        failures=$(grep -E '^  FAIL:' "$result_file" 2>/dev/null | head -5 || true)
        echo -e "${RED}FAIL${NC} (exit $rc)"
        [[ -n "$failures" ]] && echo "$failures" | sed 's/^/    /'
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
Usage: run-tests.sh [OPTIONS]

Run the quotatool test suite across multiple kernels.

Options:
  --setup         Bootstrap everything: check deps, download kernels,
                  build initramfs/rootfs, build quotatool, then run tests.
                  This is the single command for a fresh git clone.
  --smoke         Quick infrastructure check (~30s). Boots one kernel
                  per boot path (virtme, QEMU+9p, QEMU+rootfs) and
                  runs a minimal test on each. Use after --setup.
  --list          Show all kernels with boot method, tier, and status
  --jobs N        Run N kernels in parallel (default: 1 = sequential)
  --only-failed   Only re-run kernels that failed in the previous run
  --tier N        Only run kernels of tier N (1, 2, or 3)
                  Tiers: 1=actively supported, 2=recently EOL, 3=historical
  --kernel NAME   Only run the named kernel
  --host-only     Run tests on the host kernel only (no VMs, fast)
  --timeout SECS  Per-kernel timeout in seconds (default: 120)
  -v, --verbose   Verbose boot output (forces --jobs 1)
  -h, --help      Show this help
EOF
}

OPT_TIER=""
OPT_KERNEL=""
OPT_HOST_ONLY=0
OPT_SETUP=0
OPT_SMOKE=0
OPT_LIST=0
OPT_TIMEOUT="120"
OPT_VERBOSE="0"
OPT_JOBS=1
OPT_ONLY_FAILED=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup)     OPT_SETUP=1; shift ;;
        --smoke)     OPT_SMOKE=1; shift ;;
        --list)      OPT_LIST=1; shift ;;
        --jobs)      OPT_JOBS="$2"; shift 2 ;;
        -j)          OPT_JOBS="$2"; shift 2 ;;
        --only-failed) OPT_ONLY_FAILED=1; shift ;;
        --tier)      OPT_TIER="$2"; shift 2 ;;
        --kernel)    OPT_KERNEL="$2"; shift 2 ;;
        --host-only) OPT_HOST_ONLY=1; shift ;;
        --timeout)   OPT_TIMEOUT="$2"; shift 2 ;;
        -v|--verbose) OPT_VERBOSE="1"; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Verbose forces sequential (interleaved output is useless)
if [[ "$OPT_VERBOSE" == "1" && $OPT_JOBS -gt 1 ]]; then
    OPT_JOBS=1
fi

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUOTATOOL="$PROJECT_DIR/quotatool"
INITRAMFS_DIR="$SCRIPT_DIR/kernels/initramfs"
KERNELS_DIR="$SCRIPT_DIR/kernels"

# ---------------------------------------------------------------------------
# Setup / bootstrap
# ---------------------------------------------------------------------------

_setup_step() {
    echo -e "${BLUE}==> $1${NC}"
}

# Check quotatool binary exists (we don't build it — that's the user's job)
if [[ ! -x "$QUOTATOOL" ]]; then
    echo -e "${RED}quotatool binary not found.${NC} Run: ${BOLD}./configure && make${NC}"
    exit 1
fi

if [[ $OPT_SETUP -eq 1 ]]; then
    echo -e "${BOLD}Setting up test framework...${NC}"
    echo ""

    # Step 1: check host dependencies
    _setup_step "Checking host dependencies..."
    if ! "$SCRIPT_DIR/check-deps.sh"; then
        echo ""
        echo -e "${RED}Missing required dependencies. Install them and re-run.${NC}"
        exit 1
    fi
    echo ""

    # Step 2: busybox for initramfs
    if [[ ! -f "$INITRAMFS_DIR/busybox-musl" ]]; then
        _setup_step "Downloading busybox (musl-static)..."
        "$INITRAMFS_DIR/build-busybox.sh"
        echo ""
    fi

    # Step 3: build initramfs
    if [[ ! -f "$INITRAMFS_DIR/initramfs.cpio.gz" ]]; then
        _setup_step "Building initramfs..."
        "$INITRAMFS_DIR/build.sh"
        echo ""
    fi

    # Step 4: download kernels (idempotent — skips already-extracted kernels)
    _setup_step "Checking/downloading vendor kernels..."
    "$KERNELS_DIR/download.sh"
    echo ""

    # Step 5: build rootfs (for RHEL kernels without 9p)
    local_rootfs="$KERNELS_DIR/rootfs.img"
    if [[ ! -f "$local_rootfs" ]]; then
        if [[ -x "$KERNELS_DIR/build-rootfs.sh" ]]; then
            _setup_step "Building rootfs disk image (for RHEL kernels)..."
            if ! "$KERNELS_DIR/build-rootfs.sh"; then
                echo -e "${YELLOW}WARNING: rootfs build failed. RHEL kernel tests (alma/centos) will be skipped.${NC}"
            fi
            echo ""
        fi
    elif [[ "$QUOTATOOL" -nt "$local_rootfs" ]]; then
        _setup_step "Rebuilding rootfs (quotatool binary is newer)..."
        "$KERNELS_DIR/build-rootfs.sh" --force || true
        echo ""
    fi

    echo -e "${GREEN}Setup complete.${NC} Run ${BOLD}test/run-tests.sh${NC} to test."
    exit 0
fi

# ---------------------------------------------------------------------------
# Pre-flight: bail if --setup hasn't been run
# ---------------------------------------------------------------------------

if [[ ! -f "$INITRAMFS_DIR/initramfs.cpio.gz" ]]; then
    echo -e "${RED}Test infrastructure not set up.${NC} Run: ${BOLD}test/run-tests.sh --setup${NC}"
    exit 1
fi

if [[ ! -f "$CONF" ]]; then
    echo -e "${RED}No kernels.conf found.${NC} Run: ${BOLD}test/run-tests.sh --setup${NC}"
    exit 1
fi

# Check how many kernels are actually downloaded
mapfile -t _preflight_entries < <(grep -v '^\s*#' "$CONF" | grep -v '^\s*$')
_ready=0
_not_ready=0
for _entry in "${_preflight_entries[@]}"; do
    IFS='|' read -r _n _v _b _t _s <<< "$_entry"
    _n=$(echo "$_n" | xargs)
    [[ -z "$_n" ]] && continue
    _stype="${_s%%:*}"
    [[ "$_stype" == "unavailable" ]] && continue
    if [[ -n "$(find_vmlinuz "$_n" 2>/dev/null)" ]]; then
        _ready=$((_ready + 1))
    else
        _not_ready=$((_not_ready + 1))
    fi
done

if [[ $_ready -eq 0 ]]; then
    echo -e "${RED}No kernels downloaded.${NC} Run: ${BOLD}test/run-tests.sh --setup${NC}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Post-make maintenance
# ---------------------------------------------------------------------------

# Auto-rebuild rootfs if quotatool binary is newer (keeps tests in sync)
local_rootfs="$KERNELS_DIR/rootfs.img"
if [[ -f "$local_rootfs" && "$QUOTATOOL" -nt "$local_rootfs" ]]; then
    if [[ -x "$KERNELS_DIR/build-rootfs.sh" ]]; then
        _setup_step "Rebuilding rootfs (quotatool binary is newer)..."
        "$KERNELS_DIR/build-rootfs.sh" --force || true
    fi
fi

# Detect glibc minimum kernel version (affects which kernels can use 9p path)
GLIBC_MIN_KVER=""
_glibc_min=$(file /bin/sh 2>/dev/null | grep -oP 'for GNU/Linux \K[0-9.]+' || true)
if [[ -n "$_glibc_min" ]]; then
    GLIBC_MIN_KVER="$_glibc_min"
fi

# Set boot layer options
export BOOT_TIMEOUT="$OPT_TIMEOUT"
export BOOT_VERBOSE="$OPT_VERBOSE"

# Create results directory
mkdir -p "$RESULTS_DIR"

# The command to run inside each VM
GUEST_CMD="$SCRIPT_DIR/guest-run-all.sh"

# ---------------------------------------------------------------------------
# List mode
# ---------------------------------------------------------------------------

if [[ $OPT_LIST -eq 1 ]]; then
    printf "${BOLD}%-18s %-8s %-12s %-5s %-10s %s${NC}\n" \
        "KERNEL" "VERSION" "BOOT" "TIER" "STATUS" "NOTES"
    echo "------------------------------------------------------------------------"
    while IFS='|' read -r name version boot tier source; do
        name=$(echo "$name" | xargs)
        version=$(echo "$version" | xargs)
        boot=$(echo "$boot" | xargs)
        tier=$(echo "$tier" | xargs)
        local_status="" notes=""

        # Determine boot path
        boot_path="$boot"
        if [[ "$boot" == "qemu" ]]; then
            if has_9p "$name" 2>/dev/null; then
                boot_path="qemu+9p"
            else
                boot_path="qemu+rootfs"
            fi
        fi

        # Check download/extraction status
        kdir="$KERNELS_DIR/$name/extracted"
        if [[ -d "$kdir" ]] && find "$kdir" -name "vmlinu*" 2>/dev/null | grep -q .; then
            local_status="${GREEN}ready${NC}"
        else
            local_status="${RED}not downloaded${NC}"
        fi

        # Check glibc compatibility for 9p path
        if [[ -n "$GLIBC_MIN_KVER" && "$boot_path" == "qemu+9p" ]]; then
            if [[ "$(printf '%s\n' "$GLIBC_MIN_KVER" "$version" | sort -V | head -1)" != "$GLIBC_MIN_KVER" ]]; then
                notes="glibc needs kernel >=$GLIBC_MIN_KVER"
            fi
        fi

        printf "%-18s %-8s %-12s %-5s " "$name" "$version" "$boot_path" "$tier"
        echo -ne "$local_status"
        [[ -n "$notes" ]] && echo -ne "  ${YELLOW}$notes${NC}"
        echo ""
    done < <(grep -v '^\s*#' "$CONF" | grep -v '^\s*$')
    exit 0
fi

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
# Smoke test mode
# ---------------------------------------------------------------------------

if [[ $OPT_SMOKE -eq 1 ]]; then
    echo -e "${BOLD}Smoke test — one kernel per boot path${NC}"
    echo ""

    smoke_pass=0
    smoke_fail=0
    smoke_skip=0

    # A quick command that tests basic boot + quotatool binary runs.
    # Use absolute path — QEMU+9p chroot doesn't have quotatool in PATH.
    SMOKE_CMD="$QUOTATOOL -V && uname -r && echo SMOKE_PASS"

    _smoke_run() {
        local label="$1" name="$2" method="$3"
        local vmlinuz use_rootfs=0

        vmlinuz=$(find_vmlinuz "$name")
        if [[ -z "$vmlinuz" ]]; then
            printf "  %-12s %-16s " "$label" "$name"
            echo -e "${YELLOW}SKIP${NC} (kernel not downloaded)"
            smoke_skip=$((smoke_skip + 1))
            return
        fi

        printf "  %-12s %-16s " "$label" "$name"

        local rc=0 out=""
        if [[ "$method" == "rootfs" ]]; then
            local rootfs_img="$KERNELS_DIR/rootfs.img"
            if [[ ! -f "$rootfs_img" ]]; then
                echo -e "${YELLOW}SKIP${NC} (rootfs.img not built)"
                smoke_skip=$((smoke_skip + 1))
                return
            fi
            out=$(BOOT_METHOD=qemu BOOT_ROOTFS="$rootfs_img" BOOT_TIMEOUT=60 \
                boot_kernel "$vmlinuz" "/test/guest-run-all.sh ext4 1" 2>&1) || rc=$?
        else
            out=$(BOOT_METHOD="$method" BOOT_TIMEOUT=60 \
                boot_kernel "$vmlinuz" "$SMOKE_CMD" 2>&1) || rc=$?
        fi

        if [[ $rc -eq 0 ]]; then
            echo -e "${GREEN}PASS${NC}"
            smoke_pass=$((smoke_pass + 1))
        elif [[ $rc -eq 124 ]]; then
            echo -e "${RED}TIMEOUT${NC}"
            smoke_fail=$((smoke_fail + 1))
        else
            echo -e "${RED}FAIL${NC} (exit $rc)"
            smoke_fail=$((smoke_fail + 1))
            if [[ "$OPT_VERBOSE" == "1" && -n "$out" ]]; then
                echo "$out" | tail -20 | sed 's/^/    /'
            fi
        fi
    }

    # Pick one kernel per boot path:
    # virtme: first available tier-1 virtme kernel
    # qemu+9p: first available QEMU kernel with 9p
    # qemu+rootfs: first available kernel without 9p

    # Virtme path — try debian-12, then ubuntu-2404, then any virtme kernel
    for k in debian-12 ubuntu-2404 debian-11 ubuntu-2204; do
        if [[ -n "$(find_vmlinuz "$k" 2>/dev/null)" ]]; then
            _smoke_run "virtme" "$k" "virtme"
            break
        fi
    done

    # QEMU+9p path — try debian-8, then debian-7, then ubuntu-1404
    for k in debian-8 debian-7 ubuntu-1404; do
        if [[ -n "$(find_vmlinuz "$k" 2>/dev/null)" ]]; then
            _smoke_run "qemu+9p" "$k" "qemu"
            break
        fi
    done

    # QEMU+rootfs path — try alma9, then centos7, then alma8
    for k in alma9 centos7 alma8; do
        if [[ -n "$(find_vmlinuz "$k" 2>/dev/null)" ]] && ! has_9p "$k"; then
            _smoke_run "qemu+rootfs" "$k" "rootfs"
            break
        fi
    done

    echo ""
    printf "Smoke: ${GREEN}${smoke_pass} pass${NC}"
    [[ $smoke_fail -gt 0 ]] && printf ", ${RED}${smoke_fail} fail${NC}"
    [[ $smoke_skip -gt 0 ]] && printf ", ${YELLOW}${smoke_skip} skip${NC}"
    echo ""

    if [[ $smoke_fail -gt 0 || $smoke_skip -gt 0 ]]; then
        echo ""
        [[ $smoke_fail -gt 0 ]] && echo "Debug failures: run-tests.sh --kernel <name> --verbose"
        [[ $smoke_skip -gt 0 ]] && echo "Skipped kernels may need: run-tests.sh --setup"
        if [[ -n "$GLIBC_MIN_KVER" ]]; then
            echo "Note: host glibc requires kernel >=$GLIBC_MIN_KVER (qemu+9p path affected)"
        fi
    fi

    [[ $smoke_fail -gt 0 ]] && exit 1
    exit 0
fi

# ---------------------------------------------------------------------------
# Multi-kernel mode
# ---------------------------------------------------------------------------

# Re-use pre-flight data (kernels.conf already parsed, _ready/_not_ready set)
entries=("${_preflight_entries[@]}")

passed=0
failed=0
skipped=0
cached=0
declare -a failed_names=()
declare -a skipped_names=()

_start_time=$SECONDS

echo -e "${BOLD}quotatool multi-kernel test suite${NC}"
if [[ $_not_ready -gt 0 ]]; then
    echo -e "Kernels: ${_ready}/${#entries[@]} ready (${YELLOW}${_not_ready} not downloaded — run --setup to fetch${NC})"
else
    echo -e "Kernels: ${#entries[@]} in matrix"
fi
echo -e "Tests: $(ls "$SCRIPT_DIR/tests"/t-*.sh 2>/dev/null | wc -l) test scripts × 2 filesystems"
[[ $OPT_JOBS -gt 1 ]] && echo -e "Jobs: ${OPT_JOBS} parallel"
echo ""

# Clear previous results unless --only-failed (which needs them to
# know what passed last time).
if [[ $OPT_ONLY_FAILED -eq 0 ]]; then
    rm -f "$RESULTS_DIR"/*.log
fi

# ---------------------------------------------------------------------------
# Phase 1: Collect runnable kernels, handle skips
# ---------------------------------------------------------------------------

declare -a run_names=()
declare -A run_version=()
declare -A run_boot=()
declare -A run_vmlinuz=()
declare -A run_rootfs=()

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

    # Check 9p support; if missing, use rootfs disk image (RHEL kernels)
    use_rootfs=0
    if ! has_9p "$name"; then
        rootfs_img="$SCRIPT_DIR/kernels/rootfs.img"
        if [[ -f "$rootfs_img" ]]; then
            use_rootfs=1
        else
            printf "%-20s %-8s %-12s " "$name" "$version" "qemu+rootfs"
            echo -e "${YELLOW}SKIP${NC} (no 9p — build rootfs: test/kernels/build-rootfs.sh)"
            skipped=$((skipped + 1))
            skipped_names+=("$name(no-9p)")
            continue
        fi
    fi

    # Find vmlinuz
    vmlinuz=$(find_vmlinuz "$name")
    if [[ -z "$vmlinuz" ]]; then
        printf "%-20s %-8s %-12s " "$name" "$version" "$boot"
        echo -e "${YELLOW}SKIP${NC} (not downloaded)"
        skipped=$((skipped + 1))
        skipped_names+=("$name(missing)")
        continue
    fi

    # Determine actual boot path for display (matches boot.sh auto-detection)
    if [[ $use_rootfs -eq 1 ]]; then
        actual_boot="qemu+rootfs"
    else
        detected=$(boot_detect_method "$vmlinuz" 2>/dev/null || echo "unknown")
        if [[ "$detected" == "qemu" ]]; then
            actual_boot="qemu+9p"
        else
            actual_boot="$detected"
        fi
    fi

    # Skip previously passed kernels (only with --only-failed)
    if [[ $OPT_ONLY_FAILED -eq 1 ]] && _is_cached_pass "$name"; then
        _cached_summary=$(grep -E '^Results:' "$RESULTS_DIR/${name}.log" | tail -1 || true)
        printf "%-20s %-8s %-12s " "$name" "$version" "$actual_boot"
        echo -e "${GREEN}PASS${NC} $_cached_summary ${BLUE}(cached)${NC}"
        cached=$((cached + 1))
        passed=$((passed + 1))
        continue
    fi

    # Add to run list
    run_names+=("$name")
    run_version[$name]="$version"
    run_boot[$name]="$actual_boot"
    run_vmlinuz[$name]="$vmlinuz"
    run_rootfs[$name]="$use_rootfs"
done

# ---------------------------------------------------------------------------
# Phase 2: Run tests
# ---------------------------------------------------------------------------

# Run a single kernel test, writing output to .log and exit code to .rc
_run_kernel() {
    local name="$1"
    local vmlinuz="${run_vmlinuz[$name]}"
    local use_rootfs="${run_rootfs[$name]}"
    local result_file="$RESULTS_DIR/${name}.log"
    local rc=0

    if [[ $use_rootfs -eq 1 ]]; then
        BOOT_METHOD=qemu BOOT_ROOTFS="$rootfs_img" \
            boot_kernel "$vmlinuz" "/test/guest-run-all.sh" > "$result_file" 2>&1 || rc=$?
    else
        boot_kernel "$vmlinuz" "$GUEST_CMD" > "$result_file" 2>&1 || rc=$?
    fi
    echo "$rc" > "$RESULTS_DIR/${name}.rc"
}

if [[ $OPT_JOBS -le 1 ]]; then
    # --- Sequential mode: real-time output per kernel ---
    for name in "${run_names[@]}"; do
        result_file="$RESULTS_DIR/${name}.log"
        rc=0
        [[ "$OPT_VERBOSE" == "1" ]] && echo ""
        if [[ ${run_rootfs[$name]} -eq 1 ]]; then
            if [[ "$OPT_VERBOSE" == "1" ]]; then
                BOOT_METHOD=qemu BOOT_ROOTFS="$rootfs_img" \
                    boot_kernel "${run_vmlinuz[$name]}" "/test/guest-run-all.sh" 2>&1 | tee "$result_file" || rc=${PIPESTATUS[0]}
            else
                BOOT_METHOD=qemu BOOT_ROOTFS="$rootfs_img" \
                    boot_kernel "${run_vmlinuz[$name]}" "/test/guest-run-all.sh" > "$result_file" 2>&1 || rc=$?
            fi
        else
            if [[ "$OPT_VERBOSE" == "1" ]]; then
                boot_kernel "${run_vmlinuz[$name]}" "$GUEST_CMD" 2>&1 | tee "$result_file" || rc=${PIPESTATUS[0]}
            else
                boot_kernel "${run_vmlinuz[$name]}" "$GUEST_CMD" > "$result_file" 2>&1 || rc=$?
            fi
        fi

        _print_result "$name" "${run_version[$name]}" "${run_boot[$name]}" "$rc"

        if [[ $rc -eq 0 ]]; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            failed_names+=("$name")
        fi
    done
else
    # --- Parallel mode: launch up to N jobs, collect results after ---
    declare -A job_pids=()  # pid -> kernel_name
    _completed=0
    _total=${#run_names[@]}

    # Clean up stale .rc files
    rm -f "$RESULTS_DIR"/*.rc

    for name in "${run_names[@]}"; do
        # Throttle: wait for a slot if at job limit
        while [[ $(jobs -rp | wc -l) -ge $OPT_JOBS ]]; do
            # Wait for any one job to finish
            wait -n 2>/dev/null || true
            _completed=$(ls "$RESULTS_DIR"/*.rc 2>/dev/null | wc -l)
            printf "\r  Running: %d/%d completed" "$_completed" "$_total"
        done

        # Launch in background subshell (set +e so the subshell doesn't
        # exit on boot_kernel failure — we capture rc in .rc file)
        ( set +e; _run_kernel "$name" ) &
        job_pids[$!]="$name"
    done

    # Wait for all remaining jobs
    while [[ $(ls "$RESULTS_DIR"/*.rc 2>/dev/null | wc -l) -lt $_total ]]; do
        wait -n 2>/dev/null || true
        _completed=$(ls "$RESULTS_DIR"/*.rc 2>/dev/null | wc -l)
        printf "\r  Running: %d/%d completed" "$_completed" "$_total"
    done
    wait 2>/dev/null || true
    printf "\r  Running: %d/%d completed\n\n" "$_total" "$_total"

    # Print results in matrix order
    for name in "${run_names[@]}"; do
        rc=1
        if [[ -f "$RESULTS_DIR/${name}.rc" ]]; then
            rc=$(cat "$RESULTS_DIR/${name}.rc")
        fi

        _print_result "$name" "${run_version[$name]}" "${run_boot[$name]}" "$rc"

        if [[ $rc -eq 0 ]]; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            failed_names+=("$name")
        fi
    done

    # Clean up .rc files
    rm -f "$RESULTS_DIR"/*.rc
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

_elapsed=$(( SECONDS - _start_time ))
_min=$(( _elapsed / 60 ))
_sec=$(( _elapsed % 60 ))

echo ""
echo "========================================================================"
_summary="Results: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}"
[[ $cached -gt 0 ]] && _summary+=", ${BLUE}${cached} cached${NC}"
[[ $skipped -gt 0 ]] && _summary+=", ${YELLOW}${skipped} skipped${NC}"
_summary+="  (${_min}m ${_sec}s)"
echo -e "$_summary"
[[ ${#failed_names[@]} -gt 0 ]] && echo -e "Failed: ${RED}${failed_names[*]}${NC}"
[[ ${#skipped_names[@]} -gt 0 ]] && echo -e "Skipped: ${YELLOW}${skipped_names[*]}${NC}"
echo ""
echo "Logs: $RESULTS_DIR/"

[[ $failed -gt 0 ]] && exit 1
exit 0
