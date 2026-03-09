#!/bin/bash
# t-basic-soft-limit.sh — set block soft limit, verify
#
# Runs INSIDE the VM.
# Usage: t-basic-soft-limit.sh <fstype> <mountpoint>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"

FSTYPE="$1"
MNT="$2"
TEST_USER="$TEST_USER_NAME"
LIMIT="50M"
EXPECTED=51200  # 50M in 1K blocks

fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }

[[ -x "$QUOTATOOL" ]] || fail "quotatool not found at $QUOTATOOL"

# --- Test ---
"$QUOTATOOL" -u "$TEST_USER" -b -q "$LIMIT" "$MNT" || fail "quotatool exited $?"

# --- Verify ---
dump=$("$QUOTATOOL" -d -u "$TEST_USER" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

soft=$(echo "$dump" | awk '{print $4}')

if [[ "$soft" -eq "$EXPECTED" ]]; then
    echo "PASS ($FSTYPE): block soft limit is $soft (expected $EXPECTED)"
else
    fail "block soft limit is $soft, expected $EXPECTED"
fi
