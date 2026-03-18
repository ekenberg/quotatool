#!/bin/bash
# t-enforce-block-hard.sh — Verify kernel enforces hard block limit
#
# Set a hard block limit, write as test user, verify the write
# is rejected when the limit is exceeded.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

TESTDIR="$MOUNTPOINT/testuser-home"

# --- Setup: create testuser directory ---
mkdir -p "$TESTDIR"
chown $TEST_USER_NAME:$TEST_GROUP_NAME "$TESTDIR"

# --- Test 1: Write succeeds under hard limit ---
test_start "write succeeds under hard limit"
$QUOTATOOL -u $TEST_USER_NAME -b -q 200K -l 400K $MOUNTPOINT
# Write 100K (under 400K hard limit)
su -m $TEST_USER_NAME -c "dd if=/dev/zero of=$TESTDIR/file1 bs=1024 count=100 2>/dev/null"
if [ -f "$TESTDIR/file1" ]; then
    test_pass
else
    test_fail "file was not created"
fi

# --- Test 2: Write fails at hard limit ---
test_start "write rejected at hard limit"
# Try to write 500K more (would exceed 400K hard limit)
if su -m $TEST_USER_NAME -c "dd if=/dev/zero of=$TESTDIR/file2 bs=1024 count=500 2>/dev/null"; then
    # dd may succeed partially — check total usage vs hard limit
    dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
    parse_dump "$dump"
    # Usage should be capped at or near the hard limit
    if [ "$DUMP_BUSED" -le "$DUMP_BHARD" ]; then
        test_pass
    else
        test_fail "usage ($DUMP_BUSED) exceeds hard limit ($DUMP_BHARD)"
    fi
else
    # dd failed — that's the expected behavior
    test_pass
fi

# --- Test 3: Verify usage doesn't exceed hard limit ---
test_start "usage capped at hard limit"
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if [ "$DUMP_BUSED" -le 400 ]; then
    test_pass
else
    test_fail "usage ($DUMP_BUSED) exceeds hard limit (400)"
fi

# --- Cleanup ---
rm -rf "$TESTDIR"
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT

test_summary
