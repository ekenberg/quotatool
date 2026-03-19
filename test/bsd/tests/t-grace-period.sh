#!/bin/bash
# t-grace-period.sh — Verify grace period setting with -t
#
# BSD quota behavior: -t writes the grace duration to the quota file
# (via uid 0's dqb_btime). The kernel caches this at quotaon time.
# A quotaoff/quotaon cycle is required for the new value to take effect.
# This is how edquota -t works too — confirmed on both FreeBSD and OpenBSD,
# on both vnd and real disk filesystems.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# --- Test 1: Set grace period, verify with quota cycle ---
test_start "set block grace to 120s (with quota cycle)"
$QUOTATOOL -u $TEST_USER_NAME -b -q 50K -l 500K $MOUNTPOINT
$QUOTATOOL -u $TEST_USER_NAME -b -t "120seconds" $MOUNTPOINT

# Cycle quotas so kernel reloads the grace period
quotaoff $MOUNTPOINT
quotaon $MOUNTPOINT

# Exceed soft limit to trigger grace timer
TESTDIR="$MOUNTPOINT/testuser-home"
mkdir -p "$TESTDIR"
chown $TEST_USER_NAME:$TEST_GROUP_NAME "$TESTDIR"
su -m $TEST_USER_NAME -c "dd if=/dev/zero of=$TESTDIR/file1 bs=1024 count=100 2>/dev/null"

dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"

# Grace should be ~120s (between 110 and 120)
if [ "$DUMP_BGRACE" -ge 110 ] && [ "$DUMP_BGRACE" -le 120 ]; then
    test_pass
else
    test_fail "grace=$DUMP_BGRACE (expected ~120)"
fi

# Cleanup
rm -rf "$TESTDIR"
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT

# --- Test 2: Without cycle, kernel uses previous value ---
test_start "grace stays at previous value without quota cycle"
$QUOTATOOL -u $TEST_USER_NAME -b -t "60seconds" $MOUNTPOINT

# Do NOT cycle — kernel should still use 120s from test 1
$QUOTATOOL -u $TEST_USER_NAME -b -q 50K -l 500K $MOUNTPOINT
mkdir -p "$TESTDIR"
chown $TEST_USER_NAME:$TEST_GROUP_NAME "$TESTDIR"
su -m $TEST_USER_NAME -c "dd if=/dev/zero of=$TESTDIR/file1 bs=1024 count=100 2>/dev/null"

dump=$($QUOTATOOL -u $TEST_USER_NAME -d $MOUNTPOINT)
parse_dump "$dump"

# Should still be ~120s (the cycled value), not 60s
if [ "$DUMP_BGRACE" -ge 110 ] && [ "$DUMP_BGRACE" -le 120 ]; then
    test_pass
else
    test_fail "grace=$DUMP_BGRACE (expected ~120, kernel should cache until cycle)"
fi

# Cleanup
rm -rf "$TESTDIR"
$QUOTATOOL -u $TEST_USER_NAME -b -q 0K -l 0K $MOUNTPOINT

# Restore default grace (cycle to pick up the 60s from test 2)
$QUOTATOOL -u $TEST_USER_NAME -b -t "604800seconds" $MOUNTPOINT
quotaoff $MOUNTPOINT
quotaon $MOUNTPOINT

test_summary
