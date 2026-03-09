#!/bin/bash
# t-limit-isolation.sh — setting block limits must not clobber inode limits
# Usage: t-limit-isolation.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Set inode limits first
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -q 100 -l 200 "$MNT" || fail "set inode limits failed"

# Now set block limits — should NOT touch inode limits
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 50M -l 100M "$MNT" || fail "set block limits failed"

# quotatool -d fields:
# $1:id $2:mount $3:blk_used $4:blk_soft $5:blk_hard $6:blk_grace
# $7:ino_used $8:ino_soft $9:ino_hard $10:ino_grace
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

bsoft=$(echo "$dump" | awk '{print $4}')
bhard=$(echo "$dump" | awk '{print $5}')
isoft=$(echo "$dump" | awk '{print $8}')
ihard=$(echo "$dump" | awk '{print $9}')

[[ "$bsoft" -eq 51200 ]] || fail "block soft=$bsoft, expected 51200"
[[ "$bhard" -eq 102400 ]] || fail "block hard=$bhard, expected 102400"
[[ "$isoft" -eq 100 ]] || fail "inode soft=$isoft, expected 100 (clobbered!)"
[[ "$ihard" -eq 200 ]] || fail "inode hard=$ihard, expected 200 (clobbered!)"

# Now reverse: set inode limits, verify block limits unchanged
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -q 50 -l 75 "$MNT" || fail "set new inode limits failed"

dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump after inode change: $dump"

bsoft=$(echo "$dump" | awk '{print $4}')
bhard=$(echo "$dump" | awk '{print $5}')
isoft=$(echo "$dump" | awk '{print $8}')
ihard=$(echo "$dump" | awk '{print $9}')

[[ "$bsoft" -eq 51200 ]] || fail "block soft=$bsoft after inode change, expected 51200 (clobbered!)"
[[ "$bhard" -eq 102400 ]] || fail "block hard=$bhard after inode change, expected 102400 (clobbered!)"
[[ "$isoft" -eq 50 ]] || fail "inode soft=$isoft, expected 50"
[[ "$ihard" -eq 75 ]] || fail "inode hard=$ihard, expected 75"

echo "PASS ($FSTYPE): block and inode limits are isolated"
