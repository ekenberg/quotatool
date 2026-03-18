#!/bin/bash
# guest-run-all.sh — Run all BSD test scripts inside the VM
#
# Called via SSH from the host-side test runner.
# Expects quotatool to be built at /tmp/quotatool/quotatool.
#
# Usage: guest-run-all.sh <mountpoint>
set -euo pipefail

MOUNTPOINT="${1:?Usage: guest-run-all.sh <mountpoint>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="/tmp/quotatool/quotatool"

export QUOTATOOL MOUNTPOINT

if [ ! -x "$QUOTATOOL" ]; then
    echo "ERROR: quotatool not found at $QUOTATOOL"
    echo "Build it first: cd /tmp/quotatool && autoconf && ./configure && gmake"
    exit 1
fi

echo "quotatool: $($QUOTATOOL -V 2>&1 | head -1)"
echo "mountpoint: $MOUNTPOINT"
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_TESTS=0
FAILED_SCRIPTS=""

for test_script in "$SCRIPT_DIR"/tests/t-*.sh; do
    test_name=$(basename "$test_script" .sh)
    echo ""
    echo "======== $test_name ========"

    if bash "$test_script"; then
        echo "  >> $test_name: PASS"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        echo "  >> $test_name: FAIL"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        FAILED_SCRIPTS="$FAILED_SCRIPTS $test_name"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
done

echo ""
echo "================================================================"
echo "TOTAL: $TOTAL_PASS/$TOTAL_TESTS passed, $TOTAL_FAIL failed"
if [ -n "$FAILED_SCRIPTS" ]; then
    echo "FAILED:$FAILED_SCRIPTS"
fi
echo "================================================================"

[ "$TOTAL_FAIL" -eq 0 ]
