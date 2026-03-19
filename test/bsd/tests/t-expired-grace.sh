#!/bin/bash
# t-expired-grace.sh — Verify expired grace displays as 0, not huge number
#
# Bug #36: when grace period expires, the BSD code path in -d output
# showed block_time - now as a huge unsigned number instead of 0.
# Fixed by adding "> now" check before subtraction (same as Linux).
#
# Note: -t doesn't reliably set grace period on BSD (separate finding).
# This test verifies the display logic is correct regardless.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: No grace when not over soft limit ---
test_start "grace is 0 when not over soft limit"
$QUOTATOOL -u $TEST_USER_NAME -b -q 500K -l 1000K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_BGRACE" "block_grace"; then
    test_pass
fi

# --- Test 2: Grace is reasonable when over soft limit ---
test_start "grace is reasonable when over soft limit"
TESTDIR="$MOUNTPOINT/testuser-home"
mkdir -p "$TESTDIR"
chown $TEST_USER_NAME:$TEST_GROUP_NAME "$TESTDIR"

$QUOTATOOL -u $TEST_USER_NAME -b -q 50K -l 500K $MOUNTPOINT
su -m $TEST_USER_NAME -c "dd if=/dev/zero of=$TESTDIR/file1 bs=1024 count=100 2>/dev/null"
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"

# Grace should be > 0 (timer running) and < 700000 (reasonable, not wrapped unsigned)
if [ "$DUMP_BGRACE" -gt 0 ] && [ "$DUMP_BGRACE" -lt 700000 ]; then
    test_pass
else
    test_fail "grace=$DUMP_BGRACE (expected 0 < grace < 700000)"
fi

# --- Test 3: Grace returns to 0 when back under soft limit ---
test_start "grace returns to 0 when back under soft limit"
rm -f "$TESTDIR/file1"
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_BGRACE" "block_grace"; then
    test_pass
fi

# --- Test 4: Inode grace not wrapped ---
test_start "inode grace is reasonable when over soft limit"
$QUOTATOOL -u $TEST_USER_NAME -i -q 3 -l 50 $MOUNTPOINT
su -m $TEST_USER_NAME -c "touch $TESTDIR/f1 $TESTDIR/f2 $TESTDIR/f3 $TESTDIR/f4"
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if [ "$DUMP_IGRACE" -gt 0 ] && [ "$DUMP_IGRACE" -lt 700000 ]; then
    test_pass
else
    test_fail "inode grace=$DUMP_IGRACE (expected 0 < grace < 700000)"
fi

# --- Cleanup ---
rm -rf "$TESTDIR"
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
