#!/bin/bash
# t-dry-run.sh — Verify -n (dry run) doesn't modify quotas
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Setup: set known limits ---
$QUOTATOOL -u $TEST_USER_NAME -b -q 100K -l 200K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 10 -l 20 $MOUNTPOINT

# --- Test 1: Dry run block change doesn't modify ---
test_start "dry run block change has no effect"
$QUOTATOOL -n -u $TEST_USER_NAME -b -q 999K -l 999K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "100" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "200" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 2: Dry run inode change doesn't modify ---
test_start "dry run inode change has no effect"
$QUOTATOOL -n -u $TEST_USER_NAME -i -q 999 -l 999 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "10" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "20" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Cleanup ---
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
