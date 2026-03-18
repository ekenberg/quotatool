#!/bin/bash
# t-basic-soft-limit.sh — Set soft limits (block and inode) and verify
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Set soft block limit ---
test_start "set soft block limit"
$QUOTATOOL -u $TEST_USER_NAME -b -q 2048K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "2048" "$DUMP_BSOFT" "block_soft"; then
    test_pass
fi

# --- Test 2: Set soft inode limit ---
test_start "set soft inode limit"
$QUOTATOOL -u $TEST_USER_NAME -i -q 500 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "500" "$DUMP_ISOFT" "inode_soft"; then
    test_pass
fi

# --- Test 3: Both soft limits preserved independently ---
test_start "block and inode soft limits independent"
$QUOTATOOL -u $TEST_USER_NAME -b -q 1000K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 200 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "1000" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "200" "$DUMP_ISOFT" "inode_soft"; then
    test_pass
fi

# --- Cleanup ---
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
