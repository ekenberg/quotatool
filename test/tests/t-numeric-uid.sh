#!/bin/bash
# t-numeric-uid.sh — non-existent uid with : prefix
# Usage: t-numeric-uid.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Use :$TEST_NOEXIST_UID — a uid that doesn't exist in /etc/passwd
"$QUOTATOOL" -u :"$TEST_NOEXIST_UID" -b -q 50M -l 100M "$MNT" || fail "quotatool exited $?"

dump=$("$QUOTATOOL" -d -u :"$TEST_NOEXIST_UID" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

uid=$(echo "$dump" | awk '{print $1}')
soft=$(echo "$dump" | awk '{print $4}')
hard=$(echo "$dump" | awk '{print $5}')

[[ "$uid" -eq $TEST_NOEXIST_UID ]] || fail "uid=$uid, expected $TEST_NOEXIST_UID"
[[ "$soft" -eq 51200 ]] || fail "soft=$soft, expected 51200"
[[ "$hard" -eq 102400 ]] || fail "hard=$hard, expected 102400"
echo "PASS ($FSTYPE): numeric uid :$TEST_NOEXIST_UID soft=51200 hard=102400"
