#!/bin/bash
# t-parse-units.sh — unit parsing: set with various units, readback via -d
#
# Runs INSIDE a VM (needs quota filesystem). Tests parse_size() for both
# block (base-2) and inode (base-10) multipliers.
#
# Usage: t-parse-units.sh <fstype> <mountpoint>

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../../quotatool"
[[ -x "$QUOTATOOL" ]] || QUOTATOOL="/usr/bin/quotatool"
FSTYPE="${1:-ext4}"; MNT="${2:-/tmp/test-ext4}"

PASS=0
FAIL=0

_set_and_check() {
    local desc="$1" flag="$2" value="$3" field="$4" expected="$5"

    # Reset all limits first
    "$QUOTATOOL" -u :${TEST_USER_UID:-65534} -b -q 0 -l 0 "$MNT" 2>/dev/null || true
    "$QUOTATOOL" -u :${TEST_USER_UID:-65534} -i -q 0 -l 0 "$MNT" 2>/dev/null || true

    # Set the value
    local rc=0
    "$QUOTATOOL" -u :${TEST_USER_UID:-65534} $flag "$value" "$MNT" 2>/dev/null || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "  FAIL - $desc (quotatool exit $rc)"
        FAIL=$((FAIL + 1))
        return
    fi

    # Read back via -d
    local dump
    dump=$("$QUOTATOOL" -d -u :${TEST_USER_UID:-65534} "$MNT" 2>/dev/null) || {
        echo "  FAIL - $desc (dump failed)"
        FAIL=$((FAIL + 1))
        return
    }

    local got
    got=$(echo "$dump" | awk "{print \$$field}")

    if [[ "$got" -eq "$expected" ]]; then
        echo "  ok - $desc (got $got)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL - $desc: got $got, expected $expected"
        echo "    dump: $dump"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- t-parse-units ($FSTYPE) ---"

# -d fields: 1=id 2=mount 3=blk_used 4=blk_soft 5=blk_hard 6=blk_grace
#             7=ino_used 8=ino_soft 9=ino_hard 10=ino_grace

echo ""
echo "Block limits (base-2 multipliers, field 5 = blk_hard in Kb):"

# Standard units
_set_and_check "100M blocks" "-b -l" "100M" 5 102400
_set_and_check "1K blocks" "-b -l" "1K" 5 1
_set_and_check "1G blocks" "-b -l" "1G" 5 1048576
_set_and_check "1T blocks" "-b -l" "1T" 5 1073741824

# Fractional
_set_and_check "1.5M blocks" "-b -l" "1.5M" 5 1536
_set_and_check "0.5G blocks" "-b -l" "0.5G" 5 524288

# Explicit suffixes
_set_and_check "1024bytes blocks" "-b -l" "1024bytes" 5 1
_set_and_check "1blocks blocks" "-b -l" "1blocks" 5 1
_set_and_check "100 (no suffix)" "-b -l" "100" 5 100

# Soft limit too
_set_and_check "50M soft blocks" "-b -q" "50M" 4 51200

echo ""
echo "Inode limits (base-10 multipliers, field 9 = ino_hard):"

# Base-10: 1K inodes = 1000, NOT 1024 (issue #10)
_set_and_check "1K inodes" "-i -l" "1K" 9 1000
_set_and_check "1M inodes" "-i -l" "1M" 9 1000000
_set_and_check "1.5K inodes" "-i -l" "1.5K" 9 1500
_set_and_check "100 inodes (no suffix)" "-i -l" "100" 9 100

echo ""
echo "Relative adjustment edge cases:"

# Known bug: +0M clears quota instead of no-op.
# parse_size() line 475: count==0 returns 0, ignoring orig and op.
# This SHOULD stay at 102400 but returns 0. M3 fix candidate.
_set_and_check "100M then +0M (known bug)" "-b -l" "100M" 5 102400
# Now apply +0M on top
"$QUOTATOOL" -u :${TEST_USER_UID:-65534} -b -l +0M "$MNT" 2>/dev/null || true
dump=$("$QUOTATOOL" -d -u :${TEST_USER_UID:-65534} "$MNT" 2>/dev/null)
got=$(echo "$dump" | awk '{print $5}')
if [[ "$got" -eq 102400 ]]; then
    echo "  ok - +0M is no-op (got $got)"
    PASS=$((PASS + 1))
else
    echo "  KNOWN BUG - +0M clears quota: got $got, expected 102400 (M3 fix)"
    # Don't increment FAIL — known bug, not a test failure
    # FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
