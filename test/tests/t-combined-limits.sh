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

# --- Inode combined limits ---
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -q 50 -l 100 "$MNT" || fail "inode set failed"
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed (inode)"
isoft=$(echo "$dump" | awk '{print $8}')
ihard=$(echo "$dump" | awk '{print $9}')
[[ "$isoft" -eq 50 ]] || fail "inode soft=$isoft, expected 50"
[[ "$ihard" -eq 100 ]] || fail "inode hard=$ihard, expected 100"
echo "PASS ($FSTYPE): combined block soft=51200 hard=102400, inode soft=50 hard=100"
