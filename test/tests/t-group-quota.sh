#!/bin/bash
# t-group-quota.sh — set group block limits
# Usage: t-group-quota.sh <fstype> <mountpoint>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../quotatool"
FSTYPE="$1"; MNT="$2"
fail() { echo "FAIL ($FSTYPE): $*" >&2; exit 1; }
[[ -x "$QUOTATOOL" ]] || fail "quotatool not found"

# Use nogroup (gid 65534)
"$QUOTATOOL" -g nogroup -b -q 50M -l 100M "$MNT" || fail "quotatool exited $?"

dump=$("$QUOTATOOL" -d -g nogroup "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

soft=$(echo "$dump" | awk '{print $4}')
hard=$(echo "$dump" | awk '{print $5}')

[[ "$soft" -eq 51200 ]] || fail "soft=$soft, expected 51200"
[[ "$hard" -eq 102400 ]] || fail "hard=$hard, expected 102400"
echo "PASS ($FSTYPE): group quota soft=51200 hard=102400"
