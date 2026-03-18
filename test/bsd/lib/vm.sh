#!/bin/bash
# vm.sh — QEMU VM lifecycle management for BSD testing
#
# Provides functions to start, communicate with, and stop BSD VMs.
# Uses SSH over QEMU user-mode networking for all interaction.
#
# Usage:
#   source test/bsd/lib/vm.sh
#   vm_start freebsd      # boot FreeBSD from provisioned image
#   vm_wait_ssh            # block until SSH is ready
#   vm_run "uname -a"     # execute command in VM
#   vm_copy_to ./src /tmp/src   # copy files into VM
#   vm_copy_from /tmp/results . # copy files out of VM
#   vm_shutdown            # clean shutdown
#
# Environment variables (override defaults):
#   VM_MEMORY=2048         # RAM in MB
#   VM_CPUS=2              # CPU count
#   VM_SSH_PORT=2222       # host port forwarded to guest :22
#   VM_BOOT_TIMEOUT=120    # seconds to wait for SSH

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

VM_MEMORY="${VM_MEMORY:-2048}"
VM_CPUS="${VM_CPUS:-2}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"
VM_BOOT_TIMEOUT="${VM_BOOT_TIMEOUT:-120}"

# Paths — set by vm_start() based on OS
_VM_PID=""
_VM_PID_FILE=""
_VM_WORK_IMAGE=""
_VM_SSH_KEY=""

# Resolve test/bsd/ directory
_VM_BSD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_VM_IMAGES_DIR="$_VM_BSD_DIR/images"

# SSH options used everywhere
_VM_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR"

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_vm_log() { printf "\033[1m[vm]\033[0m %s\n" "$1"; }
_vm_ok()  { printf "\033[1m[vm]\033[0m \033[0;32m%s\033[0m\n" "$1"; }
_vm_err() { printf "\033[1m[vm]\033[0m \033[0;31m%s\033[0m\n" "$1" >&2; }

# ---------------------------------------------------------------------------
# vm_start <os>
#   Boot a VM from the provisioned snapshot.
#   <os>: "freebsd" or "openbsd"
#   Creates a CoW overlay so the provisioned image stays clean.
# ---------------------------------------------------------------------------
vm_start() {
    local os="${1:?Usage: vm_start <freebsd|openbsd>}"

    case "$os" in
        freebsd)
            local base_image="$_VM_IMAGES_DIR/freebsd-provisioned.qcow2"
            ;;
        openbsd)
            local base_image="$_VM_IMAGES_DIR/openbsd-provisioned.qcow2"
            ;;
        *)
            _vm_err "Unknown OS: $os (expected freebsd or openbsd)"
            return 1
            ;;
    esac

    if [ ! -f "$base_image" ]; then
        _vm_err "Provisioned image not found: $base_image"
        _vm_err "Run: test/bsd/${os}/setup.sh"
        return 1
    fi

    _VM_SSH_KEY="$_VM_IMAGES_DIR/test-key"
    if [ ! -f "$_VM_SSH_KEY" ]; then
        _vm_err "SSH key not found: $_VM_SSH_KEY"
        return 1
    fi

    # Create CoW overlay
    _VM_WORK_IMAGE="$_VM_IMAGES_DIR/${os}-test-$$.qcow2"
    qemu-img create -f qcow2 -b "$base_image" -F qcow2 "$_VM_WORK_IMAGE" >/dev/null

    _VM_PID_FILE="$_VM_IMAGES_DIR/qemu-$$.pid"

    _vm_log "Starting $os VM (${VM_MEMORY}M RAM, ${VM_CPUS} CPUs, SSH port ${VM_SSH_PORT})..."

    qemu-system-x86_64 -enable-kvm -m "${VM_MEMORY}M" -smp "$VM_CPUS" \
        -drive file="$_VM_WORK_IMAGE",if=virtio \
        -device e1000,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::${VM_SSH_PORT}-:22 \
        -display none \
        -serial null \
        -daemonize \
        -pidfile "$_VM_PID_FILE" 2>/dev/null

    _VM_PID=$(cat "$_VM_PID_FILE")
    _vm_log "QEMU PID: $_VM_PID"

    # Register cleanup trap
    trap vm_cleanup EXIT
}

# ---------------------------------------------------------------------------
# vm_wait_ssh
#   Block until SSH is ready. Respects VM_BOOT_TIMEOUT.
#   Returns 0 on success, 1 on timeout/error.
# ---------------------------------------------------------------------------
vm_wait_ssh() {
    local timeout="${VM_BOOT_TIMEOUT}"
    local elapsed=0

    _vm_log "Waiting for SSH (timeout: ${timeout}s)..."

    while [ $elapsed -lt $timeout ]; do
        if [ -n "$_VM_PID" ] && ! kill -0 "$_VM_PID" 2>/dev/null; then
            _vm_err "QEMU exited unexpectedly"
            return 1
        fi
        if ssh $_VM_SSH_OPTS -i "$_VM_SSH_KEY" -p "$VM_SSH_PORT" root@localhost "true" 2>/dev/null; then
            _vm_ok "SSH ready (${elapsed}s)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done

    _vm_err "SSH timeout after ${timeout}s"
    return 1
}

# ---------------------------------------------------------------------------
# vm_run <command> [args...]
#   Execute a command in the VM via SSH. Returns the remote exit code.
# ---------------------------------------------------------------------------
vm_run() {
    ssh $_VM_SSH_OPTS -i "$_VM_SSH_KEY" -p "$VM_SSH_PORT" root@localhost "$@"
}

# ---------------------------------------------------------------------------
# vm_copy_to <local_path> <remote_path>
#   Copy file or directory from host into VM.
# ---------------------------------------------------------------------------
vm_copy_to() {
    local src="${1:?Usage: vm_copy_to <local> <remote>}"
    local dst="${2:?Usage: vm_copy_to <local> <remote>}"
    scp $_VM_SSH_OPTS -r -i "$_VM_SSH_KEY" -P "$VM_SSH_PORT" "$src" "root@localhost:$dst"
}

# ---------------------------------------------------------------------------
# vm_copy_from <remote_path> <local_path>
#   Copy file or directory from VM to host.
# ---------------------------------------------------------------------------
vm_copy_from() {
    local src="${1:?Usage: vm_copy_from <remote> <local>}"
    local dst="${2:?Usage: vm_copy_from <remote> <local>}"
    scp $_VM_SSH_OPTS -r -i "$_VM_SSH_KEY" -P "$VM_SSH_PORT" "root@localhost:$src" "$dst"
}

# ---------------------------------------------------------------------------
# vm_shutdown
#   Clean shutdown via SSH. Waits for QEMU to exit.
# ---------------------------------------------------------------------------
vm_shutdown() {
    if [ -z "$_VM_PID" ]; then
        return 0
    fi

    _vm_log "Shutting down..."
    ssh $_VM_SSH_OPTS -i "$_VM_SSH_KEY" -p "$VM_SSH_PORT" root@localhost "shutdown -p now" 2>/dev/null || true

    # Wait for QEMU to exit (up to 30s)
    local waited=0
    while [ $waited -lt 30 ] && kill -0 "$_VM_PID" 2>/dev/null; do
        sleep 2
        waited=$((waited + 2))
    done

    # Force kill if still alive
    if kill -0 "$_VM_PID" 2>/dev/null; then
        _vm_log "Force-killing QEMU (PID $_VM_PID)"
        kill -9 "$_VM_PID" 2>/dev/null || true
    fi

    _vm_ok "VM stopped"
    _VM_PID=""
}

# ---------------------------------------------------------------------------
# vm_cleanup
#   Called on EXIT trap. Stops VM and removes temporary files.
# ---------------------------------------------------------------------------
vm_cleanup() {
    vm_shutdown

    # Remove CoW overlay (temporary, per-run)
    if [ -n "$_VM_WORK_IMAGE" ] && [ -f "$_VM_WORK_IMAGE" ]; then
        rm -f "$_VM_WORK_IMAGE"
    fi

    # Remove PID file
    if [ -n "$_VM_PID_FILE" ] && [ -f "$_VM_PID_FILE" ]; then
        rm -f "$_VM_PID_FILE"
    fi
}

# ---------------------------------------------------------------------------
# vm_is_running
#   Check if VM is alive. Returns 0 if running, 1 if not.
# ---------------------------------------------------------------------------
vm_is_running() {
    [ -n "$_VM_PID" ] && kill -0 "$_VM_PID" 2>/dev/null
}
