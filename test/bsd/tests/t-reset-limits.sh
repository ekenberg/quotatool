#!/bin/bash
# t-reset-limits.sh — Verify limits can be reset to zero
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Reset block limits ---
test_start "reset block limits"
$QUOTATOOL -u $TEST_USER_NAME -b -q 1024K -l 2048K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_BSOFT" "block_soft" && \
   assert_zero "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 2: Reset inode limits ---
test_start "reset inode limits"
$QUOTATOOL -u $TEST_USER_NAME -i -q 100 -l 200 $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_ISOFT" "inode_soft" && \
   assert_zero "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Test 3: Reset block doesn't affect inode ---
test_start "reset block preserves inode"
$QUOTATOOL -u $TEST_USER_NAME -b -q 512K -l 1024K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 50 -l 100 $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_BSOFT" "block_soft" && \
   assert_zero "$DUMP_BHARD" "block_hard" && \
   assert_equal "50" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "100" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Cleanup ---
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
