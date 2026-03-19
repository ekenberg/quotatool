#!/bin/bash
# t-enforce-inode-soft.sh — Verify inode soft limit triggers grace timer
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

TESTDIR="$MOUNTPOINT/testuser-home"

# --- Setup ---
mkdir -p "$TESTDIR"
chown $TEST_USER_NAME:$TEST_GROUP_NAME "$TESTDIR"

# --- Test 1: No inode grace before exceeding soft limit ---
test_start "no inode grace before exceeding soft limit"
$QUOTATOOL -u $TEST_USER_NAME -i -q 5 -l 50 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_IGRACE" "inode_grace"; then
    test_pass
fi

# --- Test 2: Inode grace starts after exceeding soft limit ---
test_start "inode grace starts after exceeding soft limit"
# Create 10 files (exceeds soft=5, under hard=50)
# Note: TESTDIR itself counts as 1 inode for testuser, so total = 11
for i in $(seq 1 10); do
    su -m $TEST_USER_NAME -c "touch $TESTDIR/f$i"
done
sync
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if [ "$DUMP_IGRACE" -gt 0 ]; then
    test_pass
else
    test_fail "inode grace not started (grace=$DUMP_IGRACE)"
fi

# --- Test 3: Inode grace clears when back under soft limit ---
test_start "inode grace clears when back under soft limit"
# Remove files to get clearly UNDER soft limit (soft=5, keep 2)
rm -f "$TESTDIR"/f[3-9] "$TESTDIR"/f10
sync
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_IGRACE" "inode_grace"; then
    test_pass
fi

# --- Cleanup ---
rm -rf "$TESTDIR"
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
