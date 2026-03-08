#!/bin/bash
# run-tests.sh — entry point for quotatool test framework
# Usage: ./test/run-tests.sh [KERNEL_PATH]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/lib/boot.sh"

KERNEL="${1:-/boot/vmlinuz-$(uname -r)}"

echo "=== quotatool test framework ==="
echo "Kernel: $KERNEL"

boot_kernel "$KERNEL" "$SCRIPT_DIR/guest-run-all.sh"
