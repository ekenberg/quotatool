#!/bin/bash
# boot.sh — kernel boot layer (virtme-ng / raw QEMU)
#
# Boots a kernel in a lightweight VM and runs a command inside it.
# Two code paths:
#   - Modern (>=5.4): virtme-ng with --force-9p or virtiofs
#   - Legacy (<5.4): raw QEMU with -kernel, custom initramfs, 9p share
#
# This is a library — source it, don't execute it.
#
# Public API:
#   boot_kernel KERNEL_PATH COMMAND [OPTIONS]
#
# Options (passed as environment variables):
#   BOOT_TIMEOUT    — seconds before killing a hung VM (default: 300)
#   BOOT_METHOD     — force "virtme" or "qemu" (default: auto-detect)
#   BOOT_MEMORY     — VM memory in megabytes (default: 1024)
#   BOOT_CPUS       — VM CPU count (default: 2)
#   BOOT_VERBOSE    — set to 1 for debug output (default: 0)
#   BOOT_EXTRA_ARGS — extra arguments passed to vng or qemu-system
#   BOOT_DISK       — path to extra disk image (for quota test filesystems)

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants & defaults
# ---------------------------------------------------------------------------

BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
BOOT_METHOD="${BOOT_METHOD:-auto}"
BOOT_MEMORY="${BOOT_MEMORY:-1024}"
BOOT_CPUS="${BOOT_CPUS:-2}"
BOOT_VERBOSE="${BOOT_VERBOSE:-0}"
BOOT_EXTRA_ARGS="${BOOT_EXTRA_ARGS:-}"
BOOT_DISK="${BOOT_DISK:-}"

# Minimum kernel version for virtme-ng (virtiofs requires 5.4+).
# With --force-9p this might work on older kernels too (Q4 investigation).
_VIRTME_MIN_VERSION="5.4"

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_boot_log() {
    if [[ "$BOOT_VERBOSE" == "1" ]]; then
        echo "[boot] $*" >&2
    fi
}

_boot_die() {
    echo "[boot] FATAL: $*" >&2
    return 1
}

# Compare two dotted version strings: returns 0 if $1 >= $2.
_version_ge() {
    local v1="$1" v2="$2"
    # Sort with version sort; if v2 comes first (or equal), v1 >= v2.
    local lower
    lower=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)
    [[ "$lower" == "$v2" ]]
}

# Extract kernel version from a vmlinuz path.
# Tries several strategies:
#   1. Parse version from filename (vmlinuz-5.15.0-91-generic)
#   2. Use `file` command on the binary
#   3. Give up (return "unknown")
_extract_kernel_version() {
    local kernel_path="$1"
    local basename
    basename=$(basename "$kernel_path")

    # Strategy 1: filename like vmlinuz-X.Y.Z... or vmlinux-X.Y.Z...
    if [[ "$basename" =~ ^vmlinu[xz]-([0-9]+\.[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # Strategy 2: `file` command often reports version string
    if command -v file >/dev/null 2>&1; then
        local file_out
        file_out=$(file "$kernel_path" 2>/dev/null || true)
        if [[ "$file_out" =~ version[[:space:]]+([0-9]+\.[0-9]+) ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    fi

    # Strategy 3: strings + grep (heavier, but catches more)
    if command -v strings >/dev/null 2>&1; then
        local ver
        ver=$(strings "$kernel_path" 2>/dev/null \
              | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+' \
              | head -n1 || true)
        if [[ -n "$ver" ]]; then
            # Return just major.minor
            echo "$ver" | grep -oP '^[0-9]+\.[0-9]+'
            return 0
        fi
    fi

    echo "unknown"
    return 1
}

# Check whether virtme-ng (vng) is available.
_have_virtme() {
    command -v vng >/dev/null 2>&1
}

# Check whether qemu-system-x86_64 is available.
_have_qemu() {
    command -v qemu-system-x86_64 >/dev/null 2>&1
}

# Check whether KVM is usable.
_have_kvm() {
    [[ -r /dev/kvm && -w /dev/kvm ]]
}

# ---------------------------------------------------------------------------
# Boot method detection
# ---------------------------------------------------------------------------

# Determine the best boot method for a given kernel.
#
# Returns "virtme" or "qemu" on stdout.
# Returns 1 if no viable method is available.
#
# Decision logic:
#   1. If BOOT_METHOD is set to "virtme" or "qemu", honour it.
#   2. If kernel version >= 5.4 and vng is available: virtme.
#   3. If kernel version < 5.4 and vng is available: still try virtme
#      with --force-9p (Q4: this may work on older kernels).
#   4. If vng is unavailable: qemu (if available).
#   5. Nothing available: error.
_detect_boot_method() {
    local kernel_path="$1"

    # Explicit override
    if [[ "$BOOT_METHOD" != "auto" ]]; then
        case "$BOOT_METHOD" in
            virtme)
                if ! _have_virtme; then
                    _boot_die "BOOT_METHOD=virtme but vng not found"; return 1
                fi
                echo "virtme"
                return 0
                ;;
            qemu)
                if ! _have_qemu; then
                    _boot_die "BOOT_METHOD=qemu but qemu-system-x86_64 not found"; return 1
                fi
                echo "qemu"
                return 0
                ;;
            *)
                _boot_die "Unknown BOOT_METHOD='$BOOT_METHOD' (expected: auto, virtme, qemu)"
                return 1
                ;;
        esac
    fi

    # Auto-detect
    local kver
    kver=$(_extract_kernel_version "$kernel_path") || kver="unknown"

    if _have_virtme; then
        if [[ "$kver" == "unknown" ]] || _version_ge "$kver" "$_VIRTME_MIN_VERSION"; then
            _boot_log "Auto-detected: virtme (kernel $kver >= $_VIRTME_MIN_VERSION)"
            echo "virtme"
            return 0
        else
            # Older kernel — still try virtme with --force-9p.
            # This is the Q4 bet: 9p may work back to 2.6.14.
            _boot_log "Auto-detected: virtme with --force-9p (kernel $kver < $_VIRTME_MIN_VERSION)"
            echo "virtme"
            return 0
        fi
    fi

    if _have_qemu; then
        _boot_log "Auto-detected: qemu (vng not available)"
        echo "qemu"
        return 0
    fi

    _boot_die "No boot method available: need vng (virtme-ng) or qemu-system-x86_64"
    return 1
}

# ---------------------------------------------------------------------------
# virtme-ng boot path
# ---------------------------------------------------------------------------

# Boot a kernel using virtme-ng and run a command inside the VM.
#
# virtme-ng mounts the host filesystem as a CoW overlay inside the guest.
# The guest runs as root. Exit code propagates to the host.
#
# For kernels < 5.4, --force-9p is used (virtiofs requires 5.4+).
#
# Args:
#   $1 — path to vmlinuz
#   $2 — command or script to run inside the VM
#
# Returns: the exit code from the guest command.
_boot_virtme() {
    local kernel_path="$1"
    local command="$2"

    if ! _have_virtme; then
        _boot_die "vng (virtme-ng) not found in PATH"; return 1
    fi

    local kver
    kver=$(_extract_kernel_version "$kernel_path") || kver="unknown"

    # Build vng argument list
    local -a vng_args=()

    # Kernel to boot
    vng_args+=(-r "$kernel_path")

    # Memory
    vng_args+=(-m "${BOOT_MEMORY}M")

    # CPU count
    vng_args+=(--cpus "$BOOT_CPUS")

    # Force 9p for older kernels (no virtiofs before 5.4)
    if [[ "$kver" != "unknown" ]] && ! _version_ge "$kver" "$_VIRTME_MIN_VERSION"; then
        _boot_log "Kernel $kver < $_VIRTME_MIN_VERSION: using --force-9p"
        vng_args+=(--force-9p)
    fi

    # Extra disk for quota test filesystems
    if [[ -n "$BOOT_DISK" ]]; then
        if [[ ! -f "$BOOT_DISK" ]]; then
            _boot_die "BOOT_DISK='$BOOT_DISK' does not exist"; return 1
        fi
        vng_args+=(--disk "$BOOT_DISK")
    fi

    # Extra user-supplied arguments
    if [[ -n "$BOOT_EXTRA_ARGS" ]]; then
        # Word-split intentionally
        # shellcheck disable=SC2206
        vng_args+=($BOOT_EXTRA_ARGS)
    fi

    # The command to execute inside the VM.
    # vng runs it via: vng [opts] -- COMMAND
    vng_args+=(--)
    vng_args+=("$command")

    _boot_log "Running: vng ${vng_args[*]}"

    # Temporary file for capturing output
    local output_file
    output_file=$(mktemp "${TMPDIR:-/tmp}/boot-output.XXXXXX")

    local exit_code=0

    # Run with timeout. Capture stdout+stderr to file AND pass through
    # to our stdout (so callers can capture it).
    if ! timeout --signal=KILL "$BOOT_TIMEOUT" \
         vng "${vng_args[@]}" \
         > "$output_file" 2>&1; then
        exit_code=$?
    fi

    # Print captured output
    cat "$output_file"

    # Detect timeout (KILL signal = 128+9 = 137)
    if [[ $exit_code -eq 137 ]]; then
        echo "[boot] VM killed after ${BOOT_TIMEOUT}s timeout" >&2
        rm -f "$output_file"
        return 124  # standard timeout exit code
    fi

    rm -f "$output_file"
    return $exit_code
}

# ---------------------------------------------------------------------------
# Raw QEMU boot path (legacy kernels)
# ---------------------------------------------------------------------------

# Boot a kernel using raw QEMU and run a command inside the VM.
#
# This path is for kernels that can't use virtme-ng (if Q4 shows that
# --force-9p doesn't work on old kernels). Uses:
#   - qemu-system-x86_64 with -kernel flag (direct boot, no bootloader)
#   - Custom initramfs containing busybox + test tools
#   - 9p filesystem sharing for host<->guest file exchange
#   - isa-debug-exit device for exit code propagation
#
# Args:
#   $1 — path to vmlinuz
#   $2 — command or script to run inside the VM
#
# Returns: the exit code from the guest command.
_boot_qemu() {
    local kernel_path="$1"
    local command="$2"

    # Q4 investigation may eliminate this path entirely.
    # If virtme-ng --force-9p works on 3.x/4.x kernels, we don't need
    # the raw QEMU path. Keep this stub until Q4 is resolved.
    _boot_die "Legacy QEMU boot path not yet implemented.

This path is needed only if virtme-ng --force-9p fails on kernels < 5.4.
Resolve Q4 (test vng --force-9p on a 4.x/3.x kernel) before investing
in the raw QEMU + initramfs approach.

To test Q4:
  1. Download a 4.x kernel (e.g., ubuntu-1804 4.15)
  2. Run: vng --force-9p -r <vmlinuz-4.15> -- uname -r
  3. If it prints the version → Q4 resolved, this path unnecessary
  4. If it fails → implement this path (task 3.4 in step-plan)"
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Boot a kernel and run a command inside the VM.
#
# Usage:
#   boot_kernel /path/to/vmlinuz "uname -r"
#   boot_kernel /path/to/vmlinuz "/path/to/test-script.sh"
#
# Options are controlled via environment variables (see top of file).
#
# Output:
#   stdout — whatever the guest command printed
#   stderr — boot layer diagnostic messages (if BOOT_VERBOSE=1)
#   exit code — the guest command's exit code, or:
#     124 — VM timed out
#     1   — boot infrastructure error
#
# Examples:
#   # Basic usage: boot and run a command
#   boot_kernel /boot/vmlinuz-$(uname -r) "uname -r"
#
#   # With a test disk for quota testing
#   BOOT_DISK=/tmp/quota-test.img boot_kernel /boot/vmlinuz "test.sh"
#
#   # Verbose, with 60s timeout
#   BOOT_TIMEOUT=60 BOOT_VERBOSE=1 boot_kernel /boot/vmlinuz "test.sh"
#
#   # Force raw QEMU path
#   BOOT_METHOD=qemu boot_kernel /boot/vmlinuz "test.sh"
boot_kernel() {
    local kernel_path="${1:-}"
    local command="${2:-}"

    # Validate arguments
    if [[ -z "$kernel_path" ]]; then
        _boot_die "Usage: boot_kernel KERNEL_PATH COMMAND"; return 1
    fi
    if [[ -z "$command" ]]; then
        _boot_die "Usage: boot_kernel KERNEL_PATH COMMAND"; return 1
    fi
    if [[ ! -f "$kernel_path" ]]; then
        _boot_die "Kernel not found: $kernel_path"; return 1
    fi

    # Detect boot method
    local method
    method=$(_detect_boot_method "$kernel_path") || return 1
    _boot_log "Boot method: $method"
    _boot_log "Kernel: $kernel_path"
    _boot_log "Command: $command"
    _boot_log "Timeout: ${BOOT_TIMEOUT}s"
    _boot_log "Memory: ${BOOT_MEMORY}M"
    _boot_log "CPUs: $BOOT_CPUS"

    # Warn if KVM is not available (will be very slow)
    if ! _have_kvm; then
        echo "[boot] WARNING: /dev/kvm not accessible — VM will use emulation (very slow)" >&2
    fi

    # Dispatch
    case "$method" in
        virtme) _boot_virtme "$kernel_path" "$command" ;;
        qemu)   _boot_qemu "$kernel_path" "$command" ;;
        *)      _boot_die "Unknown boot method: $method"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Convenience: boot the host's running kernel
# ---------------------------------------------------------------------------

# Boot the currently running kernel and run a command.
# Useful for quick smoke tests without specifying a kernel path.
#
# Usage:
#   boot_host_kernel "uname -r"
boot_host_kernel() {
    local command="${1:-}"
    if [[ -z "$command" ]]; then
        _boot_die "Usage: boot_host_kernel COMMAND"; return 1
    fi

    local host_kernel="/boot/vmlinuz-$(uname -r)"
    if [[ ! -f "$host_kernel" ]]; then
        _boot_die "Host kernel not found at $host_kernel"; return 1
    fi

    boot_kernel "$host_kernel" "$command"
}

# ---------------------------------------------------------------------------
# Introspection helpers (useful for the orchestrator / debugging)
# ---------------------------------------------------------------------------

# Print which boot method would be used for a kernel, without booting.
#
# Usage:
#   boot_detect_method /path/to/vmlinuz
#   # prints: "virtme" or "qemu"
boot_detect_method() {
    local kernel_path="${1:-}"
    if [[ -z "$kernel_path" ]]; then
        _boot_die "Usage: boot_detect_method KERNEL_PATH"; return 1
    fi
    if [[ ! -f "$kernel_path" ]]; then
        _boot_die "Kernel not found: $kernel_path"; return 1
    fi
    _detect_boot_method "$kernel_path"
}

# Print the detected kernel version from a vmlinuz path.
#
# Usage:
#   boot_kernel_version /path/to/vmlinuz
#   # prints: "5.15" or "unknown"
boot_kernel_version() {
    local kernel_path="${1:-}"
    if [[ -z "$kernel_path" ]]; then
        _boot_die "Usage: boot_kernel_version KERNEL_PATH"; return 1
    fi
    _extract_kernel_version "$kernel_path"
}
