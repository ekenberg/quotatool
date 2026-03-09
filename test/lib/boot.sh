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

# Minimum kernel version for virtme-ng with --force-9p.
# Q4 result: vng works with --force-9p on >=4.9, hangs on <=4.4
# (virtio-serial devices not supported on older kernels).
# Kernels >= 5.4 use virtiofs (default), 4.9-5.3 use --force-9p.
_VIRTME_MIN_VERSION="5.4"
_VIRTME_9P_MIN_VERSION="4.9"

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
#   2. If kernel >= 4.9 and vng available: virtme (with --force-9p for <5.4).
#   3. If kernel < 4.9: raw qemu (vng hangs due to virtio-serial).
#   4. If vng unavailable: qemu (if available).
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

    if _have_virtme && { [[ "$kver" == "unknown" ]] || _version_ge "$kver" "$_VIRTME_9P_MIN_VERSION"; }; then
        if _version_ge "$kver" "$_VIRTME_MIN_VERSION" 2>/dev/null; then
            _boot_log "Auto-detected: virtme (kernel $kver >= $_VIRTME_MIN_VERSION)"
        else
            _boot_log "Auto-detected: virtme with --force-9p (kernel $kver)"
        fi
        echo "virtme"
        return 0
    fi

    if _have_qemu; then
        _boot_log "Auto-detected: qemu (kernel $kver < $_VIRTME_9P_MIN_VERSION or vng unavailable)"
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
    # Use -e (--exec) instead of -- to avoid requiring a PTS.
    # Shell-escape the command so it survives the script -qec
    # string flattening (e.g., "uname -r" → "uname\ -r").
    local escaped_cmd
    printf -v escaped_cmd '%q' "$command"
    vng_args+=(-e "$escaped_cmd")

    _boot_log "Running: vng ${vng_args[*]}"

    # Temporary file for capturing output
    local output_file
    output_file=$(mktemp "${TMPDIR:-/tmp}/boot-output.XXXXXX")

    local exit_code=0

    # vng requires a PTS (pseudo-terminal) even with -e. Wrap with
    # "script -qec" to provide one. -e propagates the child exit code.
    # Timeout wraps the whole thing to kill hung VMs.
    if ! timeout --signal=KILL "$BOOT_TIMEOUT" \
         script -qec "vng ${vng_args[*]}" /dev/null \
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
# For kernels too old for virtme-ng (< 4.9, where vng's virtio-serial
# devices hang). Uses:
#   - qemu-system-x86_64 with -kernel flag (direct boot, no bootloader)
#   - Custom initramfs (busybox + init script)
#   - 9p filesystem sharing: host root (read-only) + results dir (writable)
#   - Serial console for output (no virtio-serial)
#   - Exit code propagated via file on the results 9p share
#
# The initramfs init script chroots into the host filesystem (mounted
# via 9p), so all host tools (quotatool, mkfs, etc.) are available.
#
# Args:
#   $1 — path to vmlinuz
#   $2 — command or script to run inside the VM
#
# Returns: the exit code from the guest command.
_boot_qemu() {
    local kernel_path="$1"
    local command="$2"

    if ! _have_qemu; then
        _boot_die "qemu-system-x86_64 not found in PATH"; return 1
    fi

    # Locate initramfs (relative to boot.sh → ../kernels/initramfs/)
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local initramfs="$lib_dir/../kernels/initramfs/initramfs.cpio.gz"

    if [[ ! -f "$initramfs" ]]; then
        _boot_die "Initramfs not found at $initramfs
Run: test/kernels/initramfs/build.sh"
        return 1
    fi

    # Create a temporary working directory for results + per-boot initramfs
    local work_dir
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/qemu-work.XXXXXX")
    trap "rm -rf '$work_dir'" RETURN

    local results_dir="$work_dir/results"
    mkdir -p "$results_dir"

    # Write the command to execute
    echo "$command" > "$results_dir/cmd"

    # Build a per-boot initramfs: base + kernel-specific 9p modules.
    # cpio archives are concatenable — the kernel processes them in order.
    local boot_initramfs="$work_dir/initramfs.cpio.gz"
    cp "$initramfs" "$boot_initramfs"

    # Find and append 9p/virtio modules if the kernel ships them
    local kver_full
    kver_full=$(basename "$kernel_path" | sed 's/^vmlinu[xz]-//')
    local mod_dir=""

    # Look for modules in the extracted kernel package.
    # Walk up from vmlinuz to find the extraction root, then search for
    # modules in both /lib/modules/ and /usr/lib/modules/ (usrmerge).
    local kernel_dir
    kernel_dir=$(dirname "$kernel_path")
    # Find the "extracted" directory (walk up from vmlinuz location)
    local search_base="$kernel_dir"
    while [[ "$search_base" != "/" && "$(basename "$search_base")" != "extracted" ]]; do
        search_base=$(dirname "$search_base")
    done
    if [[ "$(basename "$search_base")" == "extracted" ]]; then
        local candidate
        # Try /lib/modules first, then /usr/lib/modules (Debian 13+)
        candidate=$(find "$search_base/lib/modules" -maxdepth 2 -name "kernel" -type d 2>/dev/null | head -1)
        if [[ -z "$candidate" ]]; then
            candidate=$(find "$search_base/usr/lib/modules" -maxdepth 2 -name "kernel" -type d 2>/dev/null | head -1)
        fi
        if [[ -n "$candidate" ]]; then
            mod_dir=$(dirname "$candidate")
        fi
    fi
    # Also try system modules
    if [[ -z "$mod_dir" && -d "/lib/modules/$kver_full" ]]; then
        mod_dir="/lib/modules/$kver_full"
    fi

    if [[ -n "$mod_dir" ]]; then
        _boot_log "Found modules at: $mod_dir"
        local mod_tmp="$work_dir/mod_overlay"
        mkdir -p "$mod_tmp/modules"

        # Resolve 9p module dependencies recursively using modinfo.
        # We need 9p.ko and all its deps loaded in dependency-first order.
        local -A collected=()  # track what we've already added
        _collect_module_deps() {
            local mod_name="$1"
            [[ -n "${collected[$mod_name]+x}" ]] && return
            collected[$mod_name]=1

            # Find module file (may be compressed: .ko, .ko.xz, .ko.zst, .ko.gz)
            local mod_file
            mod_file=$(find "$mod_dir" \( -name "${mod_name}.ko" -o -name "${mod_name}.ko.xz" \
                -o -name "${mod_name}.ko.zst" -o -name "${mod_name}.ko.gz" \) 2>/dev/null | head -1)
            [[ -z "$mod_file" ]] && return

            # Recurse into dependencies first (depth-first)
            local deps
            deps=$(modinfo "$mod_file" 2>/dev/null | grep '^depends:' | sed 's/^depends:[[:space:]]*//')
            if [[ -n "$deps" ]]; then
                local IFS=','
                for dep in $deps; do
                    dep=$(echo "$dep" | tr '-' '_')
                    _collect_module_deps "$dep"
                done
            fi

            # Decompress if needed, then copy as plain .ko for insmod
            case "$mod_file" in
                *.ko.xz)  xz -dc "$mod_file" > "$mod_tmp/modules/${mod_name}.ko" ;;
                *.ko.zst) zstd -dc "$mod_file" > "$mod_tmp/modules/${mod_name}.ko" 2>/dev/null ;;
                *.ko.gz)  gzip -dc "$mod_file" > "$mod_tmp/modules/${mod_name}.ko" ;;
                *)        cp "$mod_file" "$mod_tmp/modules/" ;;
            esac
            load_order+=("$mod_name")
            _boot_log "  added module: ${mod_name}.ko (deps: ${deps:-none})"
        }

        local -a load_order=()
        # 9p filesystem and virtio transport (host mount)
        # Order matters: virtio core → virtio PCI → 9p transport → 9p fs
        _collect_module_deps "9pnet"
        _collect_module_deps "9pnet_virtio"
        # Virtio core (modinfo reports no depends: for these, but they're
        # required by virtio_pci and virtio_blk on RHEL kernels)
        _collect_module_deps "virtio"
        _collect_module_deps "virtio_ring"
        # Virtio PCI bus (needed for virtio-9p-pci and virtio-blk-pci)
        _collect_module_deps "virtio_pci"
        _collect_module_deps "9p"
        # Quota support (may be modules on old kernels)
        _collect_module_deps "quota_tree"
        _collect_module_deps "quota_v1"
        _collect_module_deps "quota_v2"
        # Loop device (module on some Debian/CentOS kernels, built-in elsewhere)
        _collect_module_deps "loop"
        # ext4 filesystem + implicit deps (module on Debian 7/8, CentOS 6/7)
        _collect_module_deps "crc16"
        _collect_module_deps "mbcache"
        _collect_module_deps "jbd2"
        _collect_module_deps "ext4"
        # XFS filesystem + deps
        # libcrc32c has softdep on crc32c (not in depends:, only softdep:)
        _collect_module_deps "crc32c_generic"
        _collect_module_deps "crc32c"
        _collect_module_deps "libcrc32c"
        _collect_module_deps "exportfs"
        _collect_module_deps "xfs"
        # Virtio block device (needed for rootfs disk path on RHEL kernels)
        _collect_module_deps "virtio_blk"

        if [[ ${#load_order[@]} -gt 0 ]]; then
            # Write load order file so init knows the correct sequence
            printf '%s\n' "${load_order[@]}" > "$mod_tmp/modules/load_order"
            # Append as a second cpio archive
            (cd "$mod_tmp" && find . | cpio -o -H newc --quiet | gzip -9) >> "$boot_initramfs"
            _boot_log "Appended ${#load_order[@]} modules to initramfs"
        fi
    else
        _boot_log "No module directory found — assuming 9p is built-in"
    fi

    # Detect rootfs disk mode (RHEL kernels without 9p)
    local rootfs_mode=0
    if [[ -n "${BOOT_ROOTFS:-}" ]]; then
        if [[ ! -f "$BOOT_ROOTFS" ]]; then
            _boot_die "BOOT_ROOTFS='$BOOT_ROOTFS' does not exist"; return 1
        fi
        rootfs_mode=1
        _boot_log "Rootfs mode: using disk image $BOOT_ROOTFS"

        # Embed the command in a per-boot initramfs overlay at /cmd
        # (the init script reads /cmd when in rootfs mode)
        local cmd_overlay="$work_dir/cmd_overlay"
        mkdir -p "$cmd_overlay"
        echo "$command" > "$cmd_overlay/cmd"
        (cd "$cmd_overlay" && echo cmd | cpio -o -H newc --quiet | gzip -9) >> "$boot_initramfs"
    fi

    # Build QEMU argument list
    local -a qemu_args=()

    # Basic machine setup
    qemu_args+=(-machine "accel=kvm:tcg")
    qemu_args+=(-cpu host)
    qemu_args+=(-m "${BOOT_MEMORY}M")
    qemu_args+=(-smp "$BOOT_CPUS")
    qemu_args+=(-no-reboot)
    qemu_args+=(-nographic)

    # Direct kernel boot
    qemu_args+=(-kernel "$kernel_path")
    qemu_args+=(-initrd "$boot_initramfs")
    # In verbose mode, show kernel messages (helps debug boot failures)
    if [[ "$BOOT_VERBOSE" == "1" ]]; then
        qemu_args+=(-append "console=ttyS0 loglevel=4 panic=-1")
    else
        qemu_args+=(-append "console=ttyS0 quiet loglevel=1 panic=-1")
    fi

    if [[ $rootfs_mode -eq 1 ]]; then
        # Rootfs disk mode: self-contained image with all tools and tests
        qemu_args+=(
            -drive "file=$BOOT_ROOTFS,if=virtio,format=raw,readonly=on"
        )
    else
        # 9p share: host root
        # Read-write to match vng behavior. Tests write only to /tmp and
        # loop devices inside the VM, so host files are safe in practice.
        qemu_args+=(
            -fsdev "local,id=hostroot,path=/,security_model=none"
            -device "virtio-9p-pci,fsdev=hostroot,mount_tag=hostroot"
        )

        # 9p share: results directory (writable)
        qemu_args+=(
            -fsdev "local,id=results,path=$results_dir,security_model=none"
            -device "virtio-9p-pci,fsdev=results,mount_tag=results"
        )
    fi

    # No networking
    qemu_args+=(-net none)

    _boot_log "Running: qemu-system-x86_64 ${qemu_args[*]}"

    # Capture output
    local output_file
    output_file=$(mktemp "${TMPDIR:-/tmp}/qemu-output.XXXXXX")

    local qemu_exit=0
    if ! timeout --signal=KILL "$BOOT_TIMEOUT" \
         qemu-system-x86_64 "${qemu_args[@]}" \
         > "$output_file" 2>&1; then
        qemu_exit=$?
    fi

    # Detect timeout (both modes)
    if [[ $qemu_exit -eq 137 ]]; then
        echo "[boot] VM killed after ${BOOT_TIMEOUT}s timeout" >&2
        rm -f "$output_file"
        return 124
    fi

    if [[ $rootfs_mode -eq 1 ]]; then
        # Rootfs mode: results come from serial output with exit marker
        local guest_exit=1
        local marker
        marker=$(grep -o '===QUOTATOOL_EXIT:[0-9]*===' "$output_file" | tail -1 || true)
        if [[ -n "$marker" ]]; then
            guest_exit=$(echo "$marker" | grep -o '[0-9]*')
            # Print output without the marker line
            grep -v '===QUOTATOOL_EXIT:' "$output_file" || true
        else
            _boot_log "No exit marker — guest may have crashed"
            cat "$output_file" >&2
        fi
        rm -f "$output_file"
        return "$guest_exit"
    else
        # 9p mode: results from results share
        if [[ -f "$results_dir/stdout" ]]; then
            cat "$results_dir/stdout"
        fi
        if [[ -f "$results_dir/stderr" ]]; then
            cat "$results_dir/stderr" >&2
        fi

        # If no guest output files, print raw QEMU output (boot messages, errors)
        if [[ ! -f "$results_dir/stdout" && ! -f "$results_dir/stderr" ]]; then
            _boot_log "No guest output files — showing raw QEMU output:"
            cat "$output_file" >&2
        fi

        rm -f "$output_file"

        # Read guest exit code
        if [[ -f "$results_dir/exit_code" ]]; then
            local guest_exit
            guest_exit=$(cat "$results_dir/exit_code")
            return "$guest_exit"
        else
            _boot_log "No exit_code file — guest may have crashed"
            return 1
        fi
    fi
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
