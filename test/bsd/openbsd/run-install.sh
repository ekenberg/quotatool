#!/bin/bash
# run-install.sh — Run QEMU with serial console driven by drive-installer.py
#
# Uses Python subprocess to manage bidirectional I/O with QEMU.
#
# Usage: run-install.sh <disk-image> <iso> <ssh-pubkey> <logfile> [ssh-port]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISK_IMAGE="$1"
ISO="$2"
SSH_PUBKEY="$3"
LOGFILE="$4"
SSH_PORT="${5:-2223}"

# Use a single Python process that spawns QEMU as a subprocess
# and drives the installer through its stdin/stdout.
exec python3 "$SCRIPT_DIR/drive-installer.py" "$SSH_PUBKEY" \
    "$DISK_IMAGE" "$ISO" "$SSH_PORT" 2>&1 | tee "$LOGFILE"
