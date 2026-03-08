#!/bin/bash
# guest-run-all.sh — runs all tests against all filesystems
#
# Runs INSIDE the VM. Called by run-tests.sh via boot_kernel.
# Creates each filesystem once, runs all tests against it, then tears down.

set -uo pipefail
# Note: no -e. We want to continue after test failures.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/tests"

source "$SCRIPT_DIR/lib/fs-setup.sh"

FSTYPES="ext4 xfs"
PASS=0
FAIL=0
ERRORS=""

for fstype in $FSTYPES; do
    echo ""
    echo "=== Filesystem: $fstype ==="

    MNT="/tmp/test-$fstype"

    # Create filesystem once for all tests
    if [[ "$fstype" == "xfs" ]]; then
        fs_create_xfs "$MNT" 200M
    else
        fs_create_ext4 "$MNT" 200M
    fi

    for test_script in "$TEST_DIR"/t-*.sh; do
        [[ -f "$test_script" ]] || continue
        test_name="$(basename "$test_script" .sh)"

        echo "--- $test_name ($fstype) ---"
        if bash "$test_script" "$fstype" "$MNT"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
            ERRORS="${ERRORS}  FAIL: $test_name ($fstype)\n"
        fi
    done

    # Teardown after all tests on this filesystem
    fs_teardown "$MNT"
done

echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo -e "Failures:\n$ERRORS"
    exit 1
fi
exit 0
