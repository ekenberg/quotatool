#!/bin/bash
# t-numeric-uid.sh — Verify quotatool works with numeric UIDs/GIDs
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Set limits by numeric UID ---
test_start "set limits by numeric UID"
$QUOTATOOL -u $TEST_USER_UID -b -q 256K -l 512K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_UID -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "256" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "512" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 2: Dump by name matches dump by UID ---
test_start "dump by name matches dump by UID"
dump_name=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
dump_uid=$($QUOTATOOL -u $TEST_USER_UID -d $MOUNTPOINT)
if assert_equal "$dump_name" "$dump_uid" "name vs uid dump"; then
    test_pass
fi

# --- Test 3: Set group limits by numeric GID ---
test_start "set group limits by numeric GID"
$QUOTATOOL -g $TEST_GROUP_GID -b -q 1024K -l 2048K $MOUNTPOINT
dump=$($QUOTATOOL -g $TEST_GROUP_GID -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "1024" "$DUMP_BSOFT" "block_soft" && \
   assert_equal "2048" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Cleanup ---
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -g $TEST_GROUP_NAME -b -q 0K -l 0K $MOUNTPOINT

test_summary
