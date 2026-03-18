#!/bin/bash
# common.sh — Shared test helpers for BSD test scripts
#
# Sourced by guest-run-all.sh inside the VM.
# Provides test result tracking, assertions, and user setup.

# ---------------------------------------------------------------------------
# Test state
# ---------------------------------------------------------------------------

_TESTS_RUN=0
_TESTS_PASSED=0
_TESTS_FAILED=0
_CURRENT_TEST=""

# ---------------------------------------------------------------------------
# Test user/group (must match cloud-init provisioning)
# ---------------------------------------------------------------------------

TEST_USER_NAME="testuser"
TEST_USER_UID=60000
TEST_GROUP_NAME="testgroup"
TEST_GROUP_GID=60000

# ---------------------------------------------------------------------------
# Paths (set by guest-run-all.sh before sourcing tests)
# ---------------------------------------------------------------------------

# QUOTATOOL — path to quotatool binary (set by caller)
# MOUNTPOINT — path to quota-enabled filesystem (set by caller)

# ---------------------------------------------------------------------------
# Test framework functions
# ---------------------------------------------------------------------------

test_start() {
    _CURRENT_TEST="${1:?Usage: test_start <name>}"
    _TESTS_RUN=$((_TESTS_RUN + 1))
    echo "--- TEST: $_CURRENT_TEST ---"
}

test_pass() {
    _TESTS_PASSED=$((_TESTS_PASSED + 1))
    echo "  PASS: $_CURRENT_TEST"
}

test_fail() {
    local msg="${1:-}"
    _TESTS_FAILED=$((_TESTS_FAILED + 1))
    echo "  FAIL: $_CURRENT_TEST${msg:+ — $msg}"
}

# Assert that a command succeeds
assert_success() {
    if "$@"; then
        return 0
    else
        test_fail "command failed: $*"
        return 1
    fi
}

# Assert that a command fails
assert_failure() {
    if "$@" 2>/dev/null; then
        test_fail "expected failure but got success: $*"
        return 1
    else
        return 0
    fi
}

# Assert string equality
assert_equal() {
    local expected="$1"
    local actual="$2"
    local label="${3:-}"
    if [ "$expected" = "$actual" ]; then
        return 0
    else
        test_fail "${label:+$label: }expected '$expected', got '$actual'"
        return 1
    fi
}

# Assert numeric comparison: actual >= expected
assert_ge() {
    local actual="$1"
    local expected="$2"
    local label="${3:-}"
    if [ "$actual" -ge "$expected" ] 2>/dev/null; then
        return 0
    else
        test_fail "${label:+$label: }expected >= $expected, got $actual"
        return 1
    fi
}

# Assert numeric comparison: actual == 0
assert_zero() {
    local actual="$1"
    local label="${2:-}"
    if [ "$actual" -eq 0 ] 2>/dev/null; then
        return 0
    else
        test_fail "${label:+$label: }expected 0, got $actual"
        return 1
    fi
}

# Parse quotatool -d output into variables
# Usage: parse_dump <dump_line>
# Sets: DUMP_UID DUMP_DEV DUMP_BUSED DUMP_BSOFT DUMP_BHARD DUMP_BGRACE
#       DUMP_IUSED DUMP_ISOFT DUMP_IHARD DUMP_IGRACE
parse_dump() {
    local line="$1"
    read -r DUMP_UID DUMP_DEV DUMP_BUSED DUMP_BSOFT DUMP_BHARD DUMP_BGRACE \
            DUMP_IUSED DUMP_ISOFT DUMP_IHARD DUMP_IGRACE <<< "$line"
}

# Print test summary, return 0 if all passed
test_summary() {
    echo ""
    echo "=== Results: $_TESTS_PASSED/$_TESTS_RUN passed, $_TESTS_FAILED failed ==="
    [ "$_TESTS_FAILED" -eq 0 ]
}
