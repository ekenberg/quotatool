#!/bin/bash
# t-enforce-block-hard.sh — exceed block hard limit, verify write rejected
# Usage: t-enforce-block-hard.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Set hard=100K (100 blocks), soft=50K
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 50 -l 100 "$MNT" || fail "set limits failed"

# Write 200K as test user — should fail (exceeds hard limit)
mkdir -p "$MNT/enforce-bhard"
chmod 777 "$MNT/enforce-bhard"
if runuser -u "$TEST_USER_NAME" -- sh -c "dd if=/dev/zero of=$MNT/enforce-bhard/fill bs=1K count=200 2>/dev/null"; then
    # dd might "succeed" but write fewer bytes. Check actual size.
    actual=$(du -k "$MNT/enforce-bhard/fill" 2>/dev/null | awk '{print $1}')
    if [[ "$actual" -ge 200 ]]; then
        fail "wrote 200K past hard limit without being stopped"
    fi
    echo "write was truncated at ${actual}K (hard limit enforced)"
else
    echo "write correctly rejected by kernel"
fi

# Verify usage does not exceed hard limit
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

used=$(echo "$dump" | awk '{print $3}')
hard=$(echo "$dump" | awk '{print $5}')

[[ "$used" -le "$hard" ]] || fail "used=$used > hard=$hard (hard limit not enforced!)"
echo "PASS ($FSTYPE): hard block limit enforced, used=$used <= hard=$hard"

# Cleanup
rm -rf "$MNT/enforce-bhard"
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 0 -l 0 "$MNT" 2>/dev/null || true
