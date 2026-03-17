#!/bin/bash
# t-grace-period.sh — set global grace period with -t, restart with -r
# Usage: t-grace-period.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Cleanup on exit (including failures)
cleanup() {
    rm -rf "$MNT/grace-test" 2>/dev/null || true
    "$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 0 -l 0 "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Use 30-second grace — short enough to verify countdown, long enough
# to not expire during the test.
GRACE=30
TOL=5  # tolerance in seconds for execution overhead

# Set global block grace period
"$QUOTATOOL" -u -b -t "${GRACE} seconds" "$MNT" || fail "set grace period failed"

# Set a low soft limit for test user, no hard limit
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 1 -l 0 "$MNT" || fail "set soft limit failed"

# Write data to exceed soft limit (triggers grace period)
mkdir -p "$MNT/grace-test"
chmod 777 "$MNT/grace-test"
runuser -u "$TEST_USER_NAME" -- sh -c "dd if=/dev/zero of=$MNT/grace-test/fill bs=1K count=100 2>/dev/null" \
    || fail "write as test user failed"

# XFS uses lazy quota metadata writeback — the grace timer is set in
# memory on write but not visible via quotactl until synced to disk.
[[ "$FSTYPE" == "xfs" ]] && sync -f "$MNT"

# quotatool -d fields:
# $1:id $2:mount $3:blk_used $4:blk_soft $5:blk_hard $6:blk_grace
# $7:ino_used $8:ino_soft $9:ino_hard $10:ino_grace
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump after exceeding soft: $dump"

grace_b=$(echo "$dump" | awk '{print $6}')
[[ "$grace_b" -ge $((GRACE - TOL)) && "$grace_b" -le $((GRACE + TOL)) ]] \
    || fail "grace_b=$grace_b, expected ~$GRACE"

# Wait 2 seconds, verify timer is counting down
sleep 2
dump_tick=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed (tick)"
grace_tick=$(echo "$dump_tick" | awk '{print $6}')
[[ "$grace_tick" -lt "$grace_b" ]] \
    || fail "timer not ticking: before=$grace_b after=$grace_tick"
[[ "$grace_tick" -ge $((GRACE - TOL - 2)) ]] \
    || fail "timer ticked too fast: $grace_tick (expected ~$((GRACE - 2)))"

# Restart block grace period with -r
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -r "$MNT" || fail "grace restart failed"

# The -r flag clears the old grace timer. On some kernels, the timer
# only restarts on the next user write. A tiny write ensures the kernel
# re-evaluates quota state and starts a fresh grace timer.
runuser -u "$TEST_USER_NAME" -- sh -c "echo x >> $MNT/grace-test/fill" \
    || fail "trigger write after -r failed"
[[ "$FSTYPE" == "xfs" ]] && sync -f "$MNT"

dump2=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed after restart"
echo "dump after -r: $dump2"

grace_b2=$(echo "$dump2" | awk '{print $6}')
# After restart, grace should reset to full period (~GRACE).
# Must be higher than grace_tick (proving it actually restarted).
[[ "$grace_b2" -ge $((GRACE - TOL)) && "$grace_b2" -le $((GRACE + TOL)) ]] \
    || fail "grace_b=$grace_b2 after restart, expected ~$GRACE"
[[ "$grace_b2" -gt "$grace_tick" ]] \
    || fail "grace did not restart: before_r=$grace_tick after_r=$grace_b2"

echo "PASS ($FSTYPE): grace period set ($grace_b), ticking ($grace_tick), restarted ($grace_b2)"
