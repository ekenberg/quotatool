#!/bin/bash
# t-relative-adjust.sh — Verify relative adjustments (+ and - operators)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Raise block soft with + ---
test_start "raise block soft with +"
$QUOTATOOL -u $TEST_USER_NAME -b -q 1000K -l 2000K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -b -q +500K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "1500" "$DUMP_BSOFT" "block_soft"; then
    test_pass
fi

# --- Test 2: Lower block soft with - ---
test_start "lower block soft with -"
$QUOTATOOL -u $TEST_USER_NAME -b -q -300K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "1200" "$DUMP_BSOFT" "block_soft"; then
    test_pass
fi

# --- Test 3: Raise block hard with + ---
test_start "raise block hard with +"
$QUOTATOOL -u $TEST_USER_NAME -b -l +1000K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "3000" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 4: Lower block hard with - ---
test_start "lower block hard with -"
$QUOTATOOL -u $TEST_USER_NAME -b -l -500K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "2500" "$DUMP_BHARD" "block_hard"; then
    test_pass
fi

# --- Test 5: Raise inode limits with + ---
test_start "raise inode limits with +"
$QUOTATOOL -u $TEST_USER_NAME -i -q 100 -l 200 $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q +50 -l +100 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "150" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "300" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Test 6: Lower inode limits with - ---
test_start "lower inode limits with -"
$QUOTATOOL -u $TEST_USER_NAME -i -q -25 -l -50 $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "125" "$DUMP_ISOFT" "inode_soft" && \
   assert_equal "250" "$DUMP_IHARD" "inode_hard"; then
    test_pass
fi

# --- Test 7: +0 is a no-op ---
test_start "+0 is a no-op"
$QUOTATOOL -u $TEST_USER_NAME -b -q 500K -l 1000K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -b -q +0K $MOUNTPOINT
dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"
if assert_equal "500" "$DUMP_BSOFT" "block_soft"; then
    test_pass
fi

# --- Cleanup ---
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -i -q 0 -l 0 $MOUNTPOINT

test_summary
