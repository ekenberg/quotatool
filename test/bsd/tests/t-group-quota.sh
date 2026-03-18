#!/bin/bash
# t-group-quota.sh — Verify group quota operations work
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Set group block limits ---
test_start "set group block limits"
$QUOTATOOL -g $TEST_GROUP_NAME -b -q 1024K -l 2048K $MOUNTPOINT
dump=$($QUOTATOOL -g $TEST_GROUP_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "1024" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "2048" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 2: Set group inode limits ---
test_start "set group inode limits"
$QUOTATOOL -g $TEST_GROUP_NAME -i -q 100 -l 200 $MOUNTPOINT
dump=$($QUOTATOOL -g $TEST_GROUP_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "100" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "200" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Test 3: User and group quotas are independent ---
test_start "user and group quotas independent"
$QUOTATOOL -u $TEST_USER_NAME -b -q 500K -l 1000K $MOUNTPOINT
$QUOTATOOL -g $TEST_GROUP_NAME -b -q 2000K -l 4000K $MOUNTPOINT
udump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
gdump=$($QUOTATOOL -g $TEST_GROUP_NAME -d $MOUNTPOINT)
parse_dump "$udump"
usoft=$DUMP_BSOFT
uhard=$DUMP_BHARD
parse_dump "$gdump"
if assert_equal "500" "$usoft" "user_block_soft" && \
   assert_equal "1000" "$uhard" "user_block_hard" && \
   assert_equal "2000" "$DUMP_BSOFT" "group_block_soft" && \
   assert_equal "4000" "$DUMP_BHARD" "group_block_hard"; then
    test_pass
fi

# --- Cleanup ---
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT
$QUOTATOOL -g $TEST_GROUP_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -g $TEST_GROUP_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
