#!/bin/bash
# t-basic-block-limit.sh — first end-to-end test
#
# Runs INSIDE the VM. Sets block hard limit with quotatool,
# verifies with quotatool -d (dump mode).
#
# Usage: called by run-tests.sh via boot_kernel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
REPO_DIR="$SCRIPT_DIR/../.."
QUOTATOOL="$REPO_DIR/quotatool"

source "$LIB_DIR/fs-setup.sh"

# /tmp is writable inside the VM (tmpfs).
MNT="/tmp/test-ext4"
TEST_USER="nobody"
LIMIT="100M"
# 100M in 1K blocks = 102400
EXPECTED=102400

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# --- Sanity checks ---
[[ -x "$QUOTATOOL" ]] || fail "quotatool binary not found at $QUOTATOOL"

# --- Setup ---
fs_create_ext4 "$MNT" 200M

# --- Test: set block hard limit ---
echo "Running: $QUOTATOOL -u $TEST_USER -b -l $LIMIT $MNT"
"$QUOTATOOL" -u "$TEST_USER" -b -l "$LIMIT" "$MNT" || fail "quotatool exited $?"

# --- Verify with quotatool -d ---
# quotatool -d output format:
#   UID MOUNTPOINT USED SOFT HARD USED SOFT HARD GRACE_B GRACE_I
#                  ^^^blocks^^^   ^^^inodes^^^
dump=$("$QUOTATOOL" -d -u "$TEST_USER" "$MNT") || fail "quotatool -d failed"
echo "dump: $dump"

hard_limit=$(echo "$dump" | awk '{print $5}')

if [[ -z "$hard_limit" ]]; then
    fail "could not parse hard limit from dump output"
fi

if [[ "$hard_limit" -eq "$EXPECTED" ]]; then
    echo "PASS: block hard limit is $hard_limit (expected $EXPECTED)"
else
    fail "block hard limit is $hard_limit, expected $EXPECTED"
fi

# --- Teardown ---
fs_teardown "$MNT"

exit 0
