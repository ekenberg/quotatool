#!/bin/bash
# t-basic-block-limit.sh — set block hard limit, verify
#
# Runs INSIDE the VM.
# Usage: t-basic-block-limit.sh <fstype> <mountpoint>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"

FSTYPE="$1"
MNT="$2"
TEST_USER="$TEST_USER_NAME"
LIMIT="100M"
EXPECTED=102400  # 100M in 1K blocks

fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }

[[ -x "$QUOTATOOL" ]] || fail "quotatool not found at $QUOTATOOL"

# --- Test ---
"$QUOTATOOL" -u "$TEST_USER" -b -l "$LIMIT" "$MNT" || fail "quotatool exited $?"

# --- Verify ---
dump=$("$QUOTATOOL" -d -u "$TEST_USER" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

hard=$(echo "$dump" | awk '{print $5}')

if [[ "$hard" -eq "$EXPECTED" ]]; then
    echo "PASS ($FSTYPE): block hard limit is $hard (expected $EXPECTED)"
else
    fail "block hard limit is $hard, expected $EXPECTED"
fi
