#!/bin/bash
# t-dump-format.sh — verify -d output format stability
#
# Runs INSIDE a VM (needs quota filesystem). Tests that -d output has
# exactly 10 space-separated fields, all numeric where expected.
# Regression guard for issue #7 (missing space between fields).
#
# Usage: t-dump-format.sh <fstype> <mountpoint>

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../../quotatool"
[[ -x "$QUOTATOOL" ]] || QUOTATOOL="/usr/bin/quotatool"
FSTYPE="${1:-ext4}"; MNT="${2:-/tmp/test-ext4}"

PASS=0
FAIL=0

_check() {
    local desc="$1" expected="$2" got="$3"
    if [[ "$got" == "$expected" ]]; then
        echo "  ok - $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL - $desc: got '$got', expected '$expected'"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- t-dump-format ($FSTYPE) ---"

# Set a known state
"$QUOTATOOL" -u :65534 -b -q 50M -l 100M "$MNT" 2>/dev/null || true
"$QUOTATOOL" -u :65534 -i -q 100 -l 200 "$MNT" 2>/dev/null || true

# Get dump
dump=$("$QUOTATOOL" -d -u :65534 "$MNT" 2>/dev/null)
echo "  dump: $dump"

# Field count must be exactly 10
field_count=$(echo "$dump" | awk '{print NF}')
_check "field count is 10" "10" "$field_count"

# Field 1: numeric uid
f1=$(echo "$dump" | awk '{print $1}')
[[ "$f1" =~ ^[0-9]+$ ]] && _check "field 1 (uid) is numeric" "yes" "yes" \
    || _check "field 1 (uid) is numeric" "yes" "no: $f1"

# Field 2: filesystem path (string, starts with /)
f2=$(echo "$dump" | awk '{print $2}')
[[ "$f2" == /* ]] && _check "field 2 (mount) starts with /" "yes" "yes" \
    || _check "field 2 (mount) starts with /" "yes" "no: $f2"

# Fields 3-6: block used, soft, hard, grace — all numeric
for i in 3 4 5 6; do
    val=$(echo "$dump" | awk "{print \$$i}")
    [[ "$val" =~ ^[0-9]+$ ]] && _check "field $i is numeric" "yes" "yes" \
        || _check "field $i is numeric" "yes" "no: $val"
done

# Fields 7-10: inode used, soft, hard, grace — all numeric
for i in 7 8 9 10; do
    val=$(echo "$dump" | awk "{print \$$i}")
    [[ "$val" =~ ^[0-9]+$ ]] && _check "field $i is numeric" "yes" "yes" \
        || _check "field $i is numeric" "yes" "no: $val"
done

# Verify known values from what we set
blk_soft=$(echo "$dump" | awk '{print $4}')
blk_hard=$(echo "$dump" | awk '{print $5}')
ino_soft=$(echo "$dump" | awk '{print $8}')
ino_hard=$(echo "$dump" | awk '{print $9}')

_check "block soft = 51200 (50M)" "51200" "$blk_soft"
_check "block hard = 102400 (100M)" "102400" "$blk_hard"
_check "inode soft = 100" "100" "$ino_soft"
_check "inode hard = 200" "200" "$ino_hard"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
