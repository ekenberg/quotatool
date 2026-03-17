#!/bin/bash
# t-enforce-inode-soft.sh — exceed inode soft limit, verify over-quota
# Usage: t-enforce-inode-soft.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Set inode soft=5, no hard limit
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -q 5 -l 0 "$MNT" || fail "set inode soft limit failed"

# Create 10 files as test user — should succeed (soft, not hard)
mkdir -p "$MNT/enforce-isoft"
chmod 777 "$MNT/enforce-isoft"
for i in $(seq 1 10); do
    runuser -u "$TEST_USER_NAME" -- sh -c "touch $MNT/enforce-isoft/file$i" \
        || fail "creating file $i should succeed (soft limit)"
done
[[ "$FSTYPE" == "xfs" ]] && sync -f "$MNT"

# quotatool -d fields:
# $1:id $2:mount $3:blk_used $4:blk_soft $5:blk_hard $6:blk_grace
# $7:ino_used $8:ino_soft $9:ino_hard $10:ino_grace
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

iused=$(echo "$dump" | awk '{print $7}')
isoft=$(echo "$dump" | awk '{print $8}')

[[ "$iused" -gt "$isoft" ]] || fail "inode used=$iused not > soft=$isoft"
echo "PASS ($FSTYPE): inode soft limit exceeded, used=$iused > soft=$isoft"

# Cleanup
rm -rf "$MNT/enforce-isoft"
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -q 0 -l 0 "$MNT" 2>/dev/null || true
