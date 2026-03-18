#!/bin/bash
# t-raise-only.sh — Verify relative adjustments (+ operator)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Raise soft block limit ---
test_start "raise soft block limit with +"
$QUOTATOOL -u $TEST_USER_NAME -b -q 1000K -l 2000K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -b -q +500K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "1500" "$DUMP_BSOFT" "block_soft"; then
    test_pass
fi

# --- Test 2: Raise hard block limit ---
test_start "raise hard block limit with +"
$QUOTATOOL -u $TEST_USER_NAME -b -l +1000K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "3000" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 3: Raise inode limits ---
test_start "raise inode limits with +"
$QUOTATOOL -u $TEST_USER_NAME -i -q 100 -l 200 $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q +50 -l +100 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "150" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "300" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Cleanup ---
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
