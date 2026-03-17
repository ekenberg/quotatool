#!/bin/bash
# t-dry-run.sh — -n flag does everything except actually setting quota
# Usage: t-dry-run.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# First clear any existing limits for non-existent uid
"$QUOTATOOL" -u ":$TEST_NOEXIST_UID" -b -q 0 -l 0 "$MNT" 2>/dev/null || true

# Dry run: set limits but -n should prevent actual change
"$QUOTATOOL" -n -u ":$TEST_NOEXIST_UID" -b -q 50M -l 100M "$MNT" || fail "dry run command failed"

dump=$("$QUOTATOOL" -d -u ":$TEST_NOEXIST_UID" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

soft=$(echo "$dump" | awk '{print $4}')
hard=$(echo "$dump" | awk '{print $5}')

[[ "$soft" -eq 0 ]] || fail "soft=$soft, expected 0 (dry run should not change)"
[[ "$hard" -eq 0 ]] || fail "hard=$hard, expected 0 (dry run should not change)"

# --- Inode dry run ---
"$QUOTATOOL" -n -u ":$TEST_NOEXIST_UID" -i -q 50 -l 100 "$MNT" || fail "inode dry run failed"
dump=$("$QUOTATOOL" -d -u ":$TEST_NOEXIST_UID" "$MNT") || fail "quotatool -d failed (inode)"
isoft=$(echo "$dump" | awk '{print $8}')
ihard=$(echo "$dump" | awk '{print $9}')
[[ "$isoft" -eq 0 ]] || fail "inode soft=$isoft, expected 0 (dry run)"
[[ "$ihard" -eq 0 ]] || fail "inode hard=$ihard, expected 0 (dry run)"
echo "PASS ($FSTYPE): -n dry run did not change quotas (block or inode)"
