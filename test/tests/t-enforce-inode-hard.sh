#!/bin/bash
# t-enforce-inode-hard.sh — exceed inode hard limit, verify creation rejected
# Usage: t-enforce-inode-hard.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Set inode soft=3, hard=5
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -q 3 -l 5 "$MNT" || fail "set inode limits failed"

# Create files as test user — first 5 should work, 6th should fail
mkdir -p "$MNT/enforce-ihard"
chmod 777 "$MNT/enforce-ihard"

created=0
for i in $(seq 1 10); do
    if runuser -u "$TEST_USER_NAME" -- sh -c "touch $MNT/enforce-ihard/file$i" 2>/dev/null; then
        created=$((created + 1))
    else
        echo "file creation blocked at file $i"
        break
    fi
done

echo "created $created files before hard limit hit"

# quotatool -d fields:
# $1:id $2:mount $3:blk_used $4:blk_soft $5:blk_hard $6:blk_grace
# $7:ino_used $8:ino_soft $9:ino_hard $10:ino_grace
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

iused=$(echo "$dump" | awk '{print $7}')
ihard=$(echo "$dump" | awk '{print $9}')

[[ "$iused" -le "$ihard" ]] || fail "inode used=$iused > hard=$ihard (not enforced!)"
[[ "$created" -le 5 ]] || fail "created $created files, expected <=5 (hard limit=5)"
echo "PASS ($FSTYPE): inode hard limit enforced, created=$created, used=$iused <= hard=$ihard"

# Cleanup
rm -rf "$MNT/enforce-ihard"
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -q 0 -l 0 "$MNT" 2>/dev/null || true
