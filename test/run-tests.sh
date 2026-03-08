#!/bin/bash
# run-tests.sh — entry point for quotatool test framework
# Usage: ./test/run-tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/lib/boot.sh"

KERNEL="${1:-/boot/vmlinuz-$(uname -r)}"

echo "=== quotatool test framework ==="
echo "Kernel: $KERNEL"
echo ""

boot_kernel "$KERNEL" "$SCRIPT_DIR/tests/t-basic-block-limit.sh"
