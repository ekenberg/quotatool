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
"$QUOTATOOL" -u nobody -b -q 100 -l 0 "$MNT" || fail "set soft limit failed"

# Write 200K as nobody — should succeed (soft limit, not hard)
mkdir -p "$MNT/enforce-bsoft"
chmod 777 "$MNT/enforce-bsoft"
runuser -u nobody -- sh -c "dd if=/dev/zero of=$MNT/enforce-bsoft/fill bs=1K count=200 2>/dev/null" \
    || fail "write past soft limit should succeed"

# Verify usage exceeds soft limit
dump=$("$QUOTATOOL" -d -u nobody "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

used=$(echo "$dump" | awk '{print $3}')
soft=$(echo "$dump" | awk '{print $4}')

[[ "$used" -gt "$soft" ]] || fail "used=$used not > soft=$soft"
echo "PASS ($FSTYPE): wrote past soft limit, used=$used > soft=$soft"

# Cleanup
rm -rf "$MNT/enforce-bsoft"
"$QUOTATOOL" -u nobody -b -q 0 -l 0 "$MNT" 2>/dev/null || true
