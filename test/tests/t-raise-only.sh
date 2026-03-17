#!/bin/bash
# t-raise-only.sh — -R flag prevents lowering quotas
# Usage: t-raise-only.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Set limit to 100M
"$QUOTATOOL" -u "$TEST_USER_NAME" -b -l 100M "$MNT" || fail "initial set failed"

# Try to lower to 50M with -R (should NOT lower)
"$QUOTATOOL" -R -u "$TEST_USER_NAME" -b -l 50M "$MNT" || fail "raise-only command failed"

dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

hard=$(echo "$dump" | awk '{print $5}')
[[ "$hard" -eq 102400 ]] || fail "hard=$hard, expected 102400 (should not have lowered)"

# Raise to 200M with -R (should work)
"$QUOTATOOL" -R -u "$TEST_USER_NAME" -b -l 200M "$MNT" || fail "raise command failed"

dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed"
echo "dump after raise: $dump"

hard=$(echo "$dump" | awk '{print $5}')
[[ "$hard" -eq 204800 ]] || fail "hard=$hard, expected 204800"

# --- Inode -R ---
"$QUOTATOOL" -u "$TEST_USER_NAME" -i -l 100 "$MNT" || fail "inode initial set failed"
"$QUOTATOOL" -R -u "$TEST_USER_NAME" -i -l 50 "$MNT" || fail "inode raise-only failed"
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed (inode)"
ihard=$(echo "$dump" | awk '{print $9}')
[[ "$ihard" -eq 100 ]] || fail "inode hard=$ihard, expected 100 (should not lower)"
"$QUOTATOOL" -R -u "$TEST_USER_NAME" -i -l 200 "$MNT" || fail "inode raise failed"
dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT") || fail "quotatool -d failed (inode raise)"
ihard=$(echo "$dump" | awk '{print $9}')
[[ "$ihard" -eq 200 ]] || fail "inode hard=$ihard, expected 200"
echo "PASS ($FSTYPE): -R prevented lower, allowed raise (block+inode)"
