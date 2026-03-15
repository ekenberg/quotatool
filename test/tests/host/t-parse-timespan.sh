#!/bin/bash
# t-parse-timespan.sh — grace period time parsing with value verification
#
# Runs INSIDE a VM (needs quota filesystem). Tests parse_timespan()
# by setting grace with -t, triggering it (exceed soft limit as
# non-root user), then reading back the grace countdown from -d.
#
# Usage: t-parse-timespan.sh <fstype> <mountpoint>

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUOTATOOL="$SCRIPT_DIR/../../../quotatool"
[[ -x "$QUOTATOOL" ]] || QUOTATOOL="/usr/bin/quotatool"
FSTYPE="${1:-ext4}"; MNT="${2:-/tmp/test-ext4}"

# Grace tests only on ext4 (XFS grace is known broken, Q5)
if [[ "$FSTYPE" == "xfs" ]]; then
    echo "--- t-parse-timespan ($FSTYPE) ---"
    echo "SKIP ($FSTYPE): grace period parsing test not supported on XFS"
    exit 0
fi

# Need TEST_USER_NAME for runuser (set by test-ids.sh via wrapper)
: "${TEST_USER_NAME:=nobody}"
: "${TEST_USER_UID:=65534}"

PASS=0
FAIL=0
TOLERANCE=5  # seconds of slack for execution time

_set_grace_and_verify() {
    local desc="$1" time_str="$2" expected_seconds="$3"

    # Step 1: clean slate — reset user limits
    "$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 0 -l 0 "$MNT" 2>/dev/null || true

    # Step 2: set global grace period
    local rc=0
    "$QUOTATOOL" -u -b -t "$time_str" "$MNT" 2>/dev/null || rc=$?

    if [[ $rc -ne 0 ]]; then
        echo "  FAIL - $desc (set grace exit $rc)"
        FAIL=$((FAIL + 1))
        return
    fi

    # Step 3: set soft limit = 1 block, no hard limit
    "$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 1 -l 0 "$MNT" 2>/dev/null || true

    # Step 4: exceed soft limit as non-root user to trigger grace
    mkdir -p "$MNT/grace-ts-test"
    chmod 777 "$MNT/grace-ts-test"
    runuser -u "$TEST_USER_NAME" -- sh -c \
        "dd if=/dev/zero of=$MNT/grace-ts-test/fill bs=1K count=100 2>/dev/null" || true

    # Step 5: read back grace from -d (field 6 = block_grace)
    local dump grace_val
    dump=$("$QUOTATOOL" -d -u "$TEST_USER_NAME" "$MNT" 2>/dev/null) || true
    grace_val=$(echo "$dump" | awk '{print $6}')

    # Step 6: cleanup
    rm -rf "$MNT/grace-ts-test" 2>/dev/null || true
    "$QUOTATOOL" -u "$TEST_USER_NAME" -b -q 0 -l 0 "$MNT" 2>/dev/null || true

    # Step 7: verify grace is within expected range
    if [[ -z "$grace_val" || "$grace_val" == "0" ]]; then
        echo "  FAIL - $desc: grace=0 (not triggered or not readable)"
        echo "    dump: $dump"
        FAIL=$((FAIL + 1))
        return
    fi

    local lower=$((expected_seconds - TOLERANCE))
    local upper=$((expected_seconds + TOLERANCE))
    [[ $lower -lt 0 ]] && lower=0

    if [[ "$grace_val" -ge "$lower" && "$grace_val" -le "$upper" ]]; then
        echo "  ok - $desc (grace=$grace_val, expected ~$expected_seconds)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL - $desc: grace=$grace_val, expected $lower..$upper"
        echo "    dump: $dump"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- t-parse-timespan ($FSTYPE) ---"

# Test representative values — each sets grace, exceeds soft, reads back
_set_grace_and_verify "1 day" "1 day" 86400
_set_grace_and_verify "2 weeks" "2 weeks" 1209600
_set_grace_and_verify "3600 seconds" "3600 seconds" 3600
_set_grace_and_verify "60 minutes" "60 minutes" 3600
_set_grace_and_verify "1 hour" "1 hour" 3600
_set_grace_and_verify "5min" "5min" 300
_set_grace_and_verify "7d" "7d" 604800
_set_grace_and_verify "3600 (no unit = seconds)" "3600" 3600

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
