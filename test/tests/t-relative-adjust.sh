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
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -l 50M "$MNT" || fail "initial set failed"

# Raise by 25M
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -l +25M "$MNT" || fail "raise failed"

dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump after +25M: $dump"

hard=$(echo "$dump" | awk '{print $5}')
# 50M + 25M = 75M = 76800 blocks
[[ "$hard" -eq 76800 ]] || fail "hard=$hard after +25M, expected 76800"

# Lower by 10M
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -l -10M "$MNT" || fail "lower failed"

dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump after -10M: $dump"

hard=$(echo "$dump" | awk '{print $5}')
# 75M - 10M = 65M = 66560 blocks
[[ "$hard" -eq 66560 ]] || fail "hard=$hard after -10M, expected 66560"

# --- Inode relative adjust ---
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -l 100 "$MNT" || fail "inode initial set failed"
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -l +50 "$MNT" || fail "inode +50 failed"
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed (inode +50)"
ihard=$(echo "$dump" | awk '{print $9}')
[[ "$ihard" -eq 150 ]] || fail "inode hard=$ihard after +50, expected 150"
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -l -30 "$MNT" || fail "inode -30 failed"
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed (inode -30)"
ihard=$(echo "$dump" | awk '{print $9}')
[[ "$ihard" -eq 120 ]] || fail "inode hard=$ihard after -30, expected 120"
echo "PASS ($FSTYPE): relative adjust block +25M/-10M, inode +50/-30"
