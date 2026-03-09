#!/bin/bash
# t-inode-limits.sh — set inode soft and hard limits
# Usage: t-inode-limits.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

"$QUOTATOOL" -u "$TEST_USER_NAME" -i -q 100 -l 200 "$MNT" || fail "quotatool exited $?"

# quotatool -d fields:
# $1:id $2:mount $3:blk_used $4:blk_soft $5:blk_hard $6:blk_grace
# $7:ino_used $8:ino_soft $9:ino_hard $10:ino_grace
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

isoft=$(echo "$dump" | awk '{print $8}')
ihard=$(echo "$dump" | awk '{print $9}')

[[ "$isoft" -eq 100 ]] || fail "inode soft=$isoft, expected 100"
[[ "$ihard" -eq 200 ]] || fail "inode hard=$ihard, expected 200"
echo "PASS ($FSTYPE): inode soft=100 hard=200"
