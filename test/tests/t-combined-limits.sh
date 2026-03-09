#!/bin/bash
# t-combined-limits.sh — set both soft and hard block limits in one call
# Usage: t-combined-limits.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

"$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 50M -l 100M "$MNT" || fail "quotatool exited $?"

dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

soft=$(echo "$dump" | awk '{print $4}')
hard=$(echo "$dump" | awk '{print $5}')

[[ "$soft" -eq 51200 ]] || fail "soft=$soft, expected 51200"
[[ "$hard" -eq 102400 ]] || fail "hard=$hard, expected 102400"
echo "PASS ($FSTYPE): combined soft=51200 hard=102400"
