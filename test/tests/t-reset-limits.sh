#!/bin/bash
# t-reset-limits.sh — set limits then reset to zero, verify cleared
# Usage: t-reset-limits.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Set block and inode limits
"$QUOTATOOL" -u nobody -b -q 50M -l 100M "$MNT" || fail "set block limits failed"
"$QUOTATOOL" -u nobody -i -q 100 -l 200 "$MNT" || fail "set inode limits failed"

# Verify they're set
dump=$("$QUOTATOOL" -d -u nobody "$MNT") || fail "quotatool -d failed"
echo "dump before reset: $dump"

bsoft=$(echo "$dump" | awk '{print $4}')
bhard=$(echo "$dump" | awk '{print $5}')
isoft=$(echo "$dump" | awk '{print $8}')
ihard=$(echo "$dump" | awk '{print $9}')

[[ "$bsoft" -gt 0 && "$bhard" -gt 0 && "$isoft" -gt 0 && "$ihard" -gt 0 ]] \
    || fail "limits not set: bsoft=$bsoft bhard=$bhard isoft=$isoft ihard=$ihard"

# Reset all to zero
"$QUOTATOOL" -u nobody -b -q 0 -l 0 "$MNT" || fail "reset block limits failed"
"$QUOTATOOL" -u nobody -i -q 0 -l 0 "$MNT" || fail "reset inode limits failed"

# Verify all cleared
dump=$("$QUOTATOOL" -d -u nobody "$MNT") || fail "quotatool -d failed after reset"
echo "dump after reset: $dump"

bsoft=$(echo "$dump" | awk '{print $4}')
bhard=$(echo "$dump" | awk '{print $5}')
isoft=$(echo "$dump" | awk '{print $8}')
ihard=$(echo "$dump" | awk '{print $9}')

[[ "$bsoft" -eq 0 ]] || fail "block soft not cleared: $bsoft"
[[ "$bhard" -eq 0 ]] || fail "block hard not cleared: $bhard"
[[ "$isoft" -eq 0 ]] || fail "inode soft not cleared: $isoft"
[[ "$ihard" -eq 0 ]] || fail "inode hard not cleared: $ihard"

echo "PASS ($FSTYPE): all limits reset to zero"
