#!/bin/bash
# t-limit-isolation.sh — Verify quotas for different users don't interfere
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Set limits on testuser, root is unaffected ---
test_start "testuser limits don't affect root"
$QUOTATOOL -u $TEST_USER_NAME -b -q 512K -l 1024K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 50 -l 100 $MOUNTPOINT
rdump=$($QUOTATOOL -u root -d $MOUNTPOINT)
parse_dump "$rdump"
if assert_zero "$DUMP_BSOFT" "root_block_soft" && \
   assert_zero "$DUMP_BHARD" "root_block_hard" && \
   assert_zero "$DUMP_ISOFT" "root_inode_soft" && \
   assert_zero "$DUMP_IHARD" "root_inode_hard"; then
    test_pass
fi

# --- Test 2: Setting root limits doesn't affect testuser ---
test_start "root limits don't affect testuser"
$QUOTATOOL -u root -b -q 8000K -l 16000K $MOUNTPOINT
udump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$udump"
if assert_equal "512" "$DUMP_BSOFT" "testuser_block_soft" && \
   assert_equal "1024" "$DUMP_BHARD" "testuser_block_hard"; then
    test_pass
fi

# --- Cleanup ---
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT
$QUOTATOOL -u root -b -q 0K -l 0K $MOUNTPOINT

test_summary
