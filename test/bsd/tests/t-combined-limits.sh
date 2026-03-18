#!/bin/bash
# t-combined-limits.sh — Set block and inode limits together, verify all fields
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Set all four limits ---
test_start "set all four limits"
$QUOTATOOL -u $TEST_USER_NAME -b -q 1024K -l 2048K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 100 -l 200 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "1024" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "2048" "$DUMP_BHARD" "block_hard" && \
   assert_equal "100" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "200" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Test 2: Modify only block limits, inode unchanged ---
test_start "modify block limits, inode unchanged"
$QUOTATOOL -u $TEST_USER_NAME -b -q 512K -l 1024K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "512" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "1024" "$DUMP_BHARD" "block_hard" && \
   assert_equal "100" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "200" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Test 3: Modify only inode limits, block unchanged ---
test_start "modify inode limits, block unchanged"
$QUOTATOOL -u $TEST_USER_NAME -i -q 50 -l 100 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "512" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "1024" "$DUMP_BHARD" "block_hard" && \
   assert_equal "50" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "100" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Test 4: Reset all to zero ---
test_start "reset all limits to zero"
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_zero "$DUMP_BSOFT" "block_soft" && \
   assert_zero "$DUMP_BHARD" "block_hard" && \
   assert_zero "$DUMP_ISOFT" "inode_soft" && \
   assert_zero "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

test_summary
