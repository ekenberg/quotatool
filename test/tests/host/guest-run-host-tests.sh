#!/bin/bash
# guest-run-host-tests.sh — runs host-side value tests inside a VM
#
# Runs INSIDE the VM. Creates a quota-enabled ext4 filesystem and
# runs the parsing/value tests against it. These tests are kernel-
# independent — they test parse.c, not kernel quota behavior.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$TEST_DIR/lib/fs-setup.sh"
source "$TEST_DIR/lib/test-ids.sh"

# Ensure required modules are loaded
modprobe loop 2>/dev/null || true
modprobe quota_v2 2>/dev/null || true
modprobe quota_tree 2>/dev/null || true

MNT="/tmp/test-host-ext4"
PASS=0
FAIL=0

# Create ext4 filesystem for the value tests
fs_create_ext4 "$MNT" 200M

# Run each host value test
for test_script in "$SCRIPT_DIR"/t-parse-*.sh "$SCRIPT_DIR"/t-dump-*.sh; do
    [[ -f "$test_script" ]] || continue
    test_name="$(basename "$test_script" .sh)"

    echo "--- $test_name (ext4) ---"
    if bash "$test_script" ext4 "$MNT"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done

# Teardown
fs_teardown "$MNT"

echo ""
echo "==============================="
echo "Host tests: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
