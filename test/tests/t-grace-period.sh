#!/bin/bash
# t-grace-period.sh — set global grace period with -t, restart with -r
# Usage: t-grace-period.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# XFS grace periods work differently — quotatool -t may not apply.
# TODO: investigate XFS grace period support
if [[ "$FSTYPE" == "xfs" ]]; then
    echo "SKIP ($FSTYPE): grace period test not yet supported on XFS"
    exit 0
fi

# Set global block grace period to 1 day (86400 seconds)
"$QUOTATOOL" -u -b -t "1 day" "$MNT" || fail "set grace period failed"

# Set a low soft limit for nobody, no hard limit
"$QUOTATOOL" -u nobody -b -q 1 -l 0 "$MNT" || fail "set soft limit failed"

# Write data to exceed soft limit (triggers grace period)
mkdir -p "$MNT/grace-test"
chmod 777 "$MNT/grace-test"
su -s /bin/sh nobody -c "dd if=/dev/zero of=$MNT/grace-test/fill bs=1K count=100 2>/dev/null" \
    || fail "write as nobody failed"

# quotatool -d fields:
# $1:id $2:mount $3:blk_used $4:blk_soft $5:blk_hard $6:blk_grace
# $7:ino_used $8:ino_soft $9:ino_hard $10:ino_grace
dump=$("$QUOTATOOL" -d -u nobody "$MNT") || fail "quotatool -d failed"
echo "dump after exceeding soft: $dump"

grace_b=$(echo "$dump" | awk '{print $6}')
[[ "$grace_b" -gt 0 ]] || fail "grace_b=$grace_b, expected >0 (grace period should be active)"

# Restart block grace period with -r
"$QUOTATOOL" -u nobody -b -r "$MNT" || fail "grace restart failed"

dump2=$("$QUOTATOOL" -d -u nobody "$MNT") || fail "quotatool -d failed after restart"
echo "dump after -r: $dump2"

grace_b2=$(echo "$dump2" | awk '{print $6}')
[[ "$grace_b2" -gt 0 ]] || fail "grace_b=$grace_b2 after restart, expected >0"

# Cleanup
rm -rf "$MNT/grace-test"
"$QUOTATOOL" -u nobody -b -q 0 -l 0 "$MNT" 2>/dev/null || true

echo "PASS ($FSTYPE): grace period set, triggered, restarted"
