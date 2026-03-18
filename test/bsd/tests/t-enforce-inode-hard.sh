#!/bin/bash
# t-enforce-inode-hard.sh — Verify kernel enforces hard inode limit
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

TESTDIR="$MOUNTPOINT/testuser-home"

# --- Setup ---
mkdir -p "$TESTDIR"
chown $TEST_USER_NAME:$TEST_GROUP_NAME "$TESTDIR"

# --- Test 1: File creation succeeds under hard limit ---
test_start "file creation succeeds under hard limit"
$QUOTATOOL -u $TEST_USER_NAME -i -q 5 -l 10 $MOUNTPOINT
su -m $TEST_USER_NAME -c "touch $TESTDIR/f1 $TESTDIR/f2 $TESTDIR/f3"
count=$(ls "$TESTDIR" | wc -l)
if [ "$count" -eq 3 ]; then
    test_pass
else
    test_fail "expected 3 files, got $count"
fi

# --- Test 2: File creation rejected at hard limit ---
test_start "file creation rejected at hard inode limit"
# Try to create 15 more files (would exceed limit of 10)
failed=0
for i in $(seq 4 20); do
    if ! su -m $TEST_USER_NAME -c "touch $TESTDIR/f$i" 2>/dev/null; then
        failed=1
        break
    fi
done
if [ "$failed" -eq 1 ]; then
    test_pass
else
    # Check if inode count is capped
    dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
    parse_dump "$dump"
    if [ "$DUMP_IUSED" -le "$DUMP_IHARD" ]; then
        test_pass
    else
        test_fail "inode usage ($DUMP_IUSED) exceeds hard limit ($DUMP_IHARD)"
    fi
fi

# --- Test 3: Inode usage doesn't exceed hard limit ---
test_start "inode usage capped at hard limit"
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if [ "$DUMP_IUSED" -le 10 ]; then
    test_pass
else
    test_fail "inode usage ($DUMP_IUSED) exceeds hard limit (10)"
fi

# --- Cleanup ---
rm -rf "$TESTDIR"
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
