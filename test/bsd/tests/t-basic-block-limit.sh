#!/bin/bash
# t-basic-block-limit.sh — Set block limits and verify via dump
#
# Runs inside the BSD VM. Tests that quotatool can set soft and hard
# block limits on a user, and that -d dump reflects the correct values.
#
# Input: $QUOTATOOL, $MOUNTPOINT set by guest-run-all.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Set soft block limit ---
test_start "set soft block limit"
$QUOTATOOL -u $TEST_USER_NAME -b -q 1024K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "1024" "$DUMP_BSOFT" "block_soft"; then
    test_pass
fi

# --- Test 2: Set hard block limit ---
test_start "set hard block limit"
$QUOTATOOL -u $TEST_USER_NAME -b -l 2048K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "2048" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 3: Both limits in one command ---
test_start "set both block limits"
$QUOTATOOL -u $TEST_USER_NAME -b -q 512K -l 1024K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "512" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "1024" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 4: Soft limit preserved when setting hard only ---
test_start "soft limit preserved when setting hard"
$QUOTATOOL -u $TEST_USER_NAME -b -q 100K -l 200K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -b -l 300K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "100" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "300" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 5: Reset limits to zero ---
test_start "reset block limits to zero"
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_BSOFT" "block_soft" && \
   assert_zero "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

test_summary
