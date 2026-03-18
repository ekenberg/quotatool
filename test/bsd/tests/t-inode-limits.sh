#!/bin/bash
# t-inode-limits.sh — Set inode (file count) limits and verify
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Set soft inode limit ---
test_start "set soft inode limit"
$QUOTATOOL -u $TEST_USER_NAME -i -q 100 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "100" "$DUMP_ISOFT" "inode_soft"; then
    test_pass
fi

# --- Test 2: Set hard inode limit ---
test_start "set hard inode limit"
$QUOTATOOL -u $TEST_USER_NAME -i -l 200 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "200" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Test 3: Both inode limits ---
test_start "set both inode limits"
$QUOTATOOL -u $TEST_USER_NAME -i -q 50 -l 100 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "50" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "100" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Test 4: Inode limits don't affect block limits ---
test_start "inode limits don't affect block limits"
$QUOTATOOL -u $TEST_USER_NAME -b -q 512K -l 1024K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 25 -l 50 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "512" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "1024" "$DUMP_BHARD" "block_hard" && \
   assert_equal "25" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "50" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Cleanup ---
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
