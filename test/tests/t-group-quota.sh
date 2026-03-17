#!/bin/bash
# t-group-quota.sh — set group block limits
# Usage: t-group-quota.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Use TEST_GROUP_NAME from test-ids.sh (e.g., nogroup on Debian, nobody on Fedora)
"$QUOTATOOL" -g "$TEST_GROUP_NAME" -b -q 50M -l 100M "$MNT" || fail "quotatool exited $?"

dump=$("$QUOTATOOL" -d -g "$TEST_GROUP_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

soft=$(echo "$dump" | awk '{print $4}')
hard=$(echo "$dump" | awk '{print $5}')

[[ "$soft" -eq 51200 ]] || fail "soft=$soft, expected 51200"
[[ "$hard" -eq 102400 ]] || fail "hard=$hard, expected 102400"

# --- Inode group limits ---
"$QUOTATOOL" -g "$TEST_GROUP_NAME" -i -q 50 -l 100 "$MNT" || fail "inode group set failed"
dump=$("$QUOTATOOL" -d -g "$TEST_GROUP_NAME" "$MNT") || fail "quotatool -d failed (inode)"
isoft=$(echo "$dump" | awk '{print $8}')
ihard=$(echo "$dump" | awk '{print $9}')
[[ "$isoft" -eq 50 ]] || fail "inode soft=$isoft, expected 50"
[[ "$ihard" -eq 100 ]] || fail "inode hard=$ihard, expected 100"
echo "PASS ($FSTYPE): group quota soft=51200 hard=102400, inode soft=50 hard=100"
