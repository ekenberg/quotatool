#!/bin/bash
# t-enforce-block-soft.sh — Verify soft limit triggers grace period
#
# Set a soft block limit, exceed it, verify grace timer starts.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

TESTDIR="$MOUNTPOINT/testuser-home"

# --- Setup ---
mkdir -p "$TESTDIR"
chown $TEST_USER_NAME:$TEST_GROUP_NAME "$TESTDIR"

# --- Test 1: No grace timer before exceeding soft limit ---
test_start "no grace timer before exceeding soft limit"
$QUOTATOOL -u $TEST_USER_NAME -b -q 100K -l 500K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_BGRACE" "block_grace"; then
    test_pass
fi

# --- Test 2: Grace timer starts after exceeding soft limit ---
test_start "grace timer starts after exceeding soft limit"
# Write 200K (exceeds 100K soft limit, under 500K hard)
su -m $TEST_USER_NAME -c "dd if=/dev/zero of=$TESTDIR/file1 bs=1024 count=200 2>/dev/null"
sync
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if [ "$DUMP_BGRACE" -gt 0 ]; then
    test_pass
else
    test_fail "grace timer not started (grace=$DUMP_BGRACE)"
fi

# --- Test 3: Grace timer clears when back under soft limit ---
test_start "grace timer clears when back under soft limit"
rm -f "$TESTDIR/file1"
sync
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_BGRACE" "block_grace"; then
    test_pass
fi

# --- Cleanup ---
rm -rf "$TESTDIR"
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT

test_summary
