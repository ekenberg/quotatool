#!/bin/bash
# t-enforce-block-soft.sh — exceed block soft limit, verify over-quota
# Usage: t-enforce-block-soft.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Set soft=100K (100 blocks), no hard limit
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 100 -l 0 "$MNT" || fail "set soft limit failed"

# Write 200K as test user — should succeed (soft limit, not hard)
mkdir -p "$MNT/enforce-bsoft"
chmod 777 "$MNT/enforce-bsoft"
runuser -u "$TEST_USER_NAME" -- sh -c "dd if=/dev/zero of=$MNT/enforce-bsoft/fill bs=1K count=200 2>/dev/null" \
    || fail "write past soft limit should succeed"
[[ "$FSTYPE" == "xfs" ]] && sync -f "$MNT"

# Verify usage exceeds soft limit
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

used=$(echo "$dump" | awk '{print $3}')
soft=$(echo "$dump" | awk '{print $4}')
grace_b=$(echo "$dump" | awk '{print $6}')

[[ "$used" -gt "$soft" ]] || fail "used=$used not > soft=$soft"
# Grace timer must be active — distinguishes working soft limit from no quota.
[[ "$grace_b" -gt 0 ]] || fail "grace_b=$grace_b, expected >0 (soft limit should trigger grace)"
echo "PASS ($FSTYPE): wrote past soft limit, used=$used > soft=$soft"

# Cleanup
rm -rf "$MNT/enforce-bsoft"
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 0 -l 0 "$MNT" 2>/dev/null || true
