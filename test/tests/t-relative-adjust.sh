#!/bin/bash
# t-relative-adjust.sh — relative quota adjustment with +/-
# Usage: t-relative-adjust.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Set base limit
"$QUOTATOOL" -u nobody -b -l 50M "$MNT" || fail "initial set failed"

# Raise by 25M
"$QUOTATOOL" -u nobody -b -l +25M "$MNT" || fail "raise failed"

dump=$("$QUOTATOOL" -d -u nobody "$MNT") || fail "quotatool -d failed"
echo "dump after +25M: $dump"

hard=$(echo "$dump" | awk '{print $5}')
# 50M + 25M = 75M = 76800 blocks
[[ "$hard" -eq 76800 ]] || fail "hard=$hard after +25M, expected 76800"

# Lower by 10M
"$QUOTATOOL" -u nobody -b -l -10M "$MNT" || fail "lower failed"

dump=$("$QUOTATOOL" -d -u nobody "$MNT") || fail "quotatool -d failed"
echo "dump after -10M: $dump"

hard=$(echo "$dump" | awk '{print $5}')
# 75M - 10M = 65M = 66560 blocks
[[ "$hard" -eq 66560 ]] || fail "hard=$hard after -10M, expected 66560"

echo "PASS ($FSTYPE): relative adjust +25M then -10M"
