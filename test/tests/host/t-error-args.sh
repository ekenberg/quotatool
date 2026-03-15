#!/bin/bash
# t-error-args.sh — argument validation tests (no root, no VM, no filesystem)
#
# Tests that bad arguments produce correct exit codes and error messages.
# All of these fail in parse_commandline() or early main() — before any
# quotactl() call. Runnable by anyone, anywhere, instantly.
#
# Usage: t-error-args.sh [path-to-quotatool]

set -uo pipefail

QUOTATOOL="${1:-$(cd "$(dirname "$0")/../../.." && pwd)/quotatool}"
[[ -x "$QUOTATOOL" ]] || { echo "FATAL: quotatool not found at $QUOTATOOL" >&2; exit 99; }

PASS=0
FAIL=0

# Check: exit code matches expected, and stderr contains expected string.
# Args: description expected_exit expected_stderr_substr quotatool_args...
_check() {
    local desc="$1" want_exit="$2" want_err="$3"
    shift 3

    local rc=0 err=""
    err=$("$QUOTATOOL" "$@" 2>&1 >/dev/null) || rc=$?

    local ok=1
    if [[ $rc -ne $want_exit ]]; then
        ok=0
    fi
    if [[ -n "$want_err" && "$err" != *"$want_err"* ]]; then
        ok=0
    fi

    if [[ $ok -eq 1 ]]; then
        echo "  ok - $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL - $desc"
        [[ $rc -ne $want_exit ]] && echo "    exit: got $rc, expected $want_exit"
        [[ -n "$want_err" && "$err" != *"$want_err"* ]] && echo "    stderr: expected '$want_err', got: $err"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- t-error-args (no root, no VM) ---"

# ERR_PARSE (exit 1) — argument structure errors
_check "no arguments" \
    1 "" \
    # (no args)

_check "-q without -b/-i" \
    1 "Must specify either block (-b) or inode (-i) before -q" \
    -u :99999 -q 100 /

_check "-l without -b/-i" \
    1 "Must specify either block (-b) or inode (-i) before -l" \
    -u :99999 -l 100 /

_check "-t without -b/-i" \
    1 "Must specify either block (-b) or inode (-i) before -t" \
    -u :99999 -t "1 day" /

_check "-r without -b/-i" \
    1 "Must specify either block (-b) or inode (-i) before -r" \
    -u :99999 -r /

_check "both -u and -g" \
    1 "Only one quota (user or group) can be set" \
    -u :1 -g :1 -b -l 100 /

_check "no filesystem argument" \
    1 "No filesystem specified" \
    -u :99999 -b -l 100

_check "no -u/-g specified" \
    1 "Must specify either user or group quota" \
    -b -l 100 /

_check "-t mixed with -l" \
    1 "Wrong options for -t" \
    -u :99999 -b -t "1 day" -l 100 /

_check "-r mixed with -l" \
    1 "Wrong options for -r" \
    -u :99999 -b -r -l 100 /

_check "unknown option -Z" \
    1 "Unrecognized option" \
    -u :99999 -b -Z /

# ERR_ARG (exit 2) — valid syntax but bad values
_check "nonexistent user" \
    2 "does not exist" \
    -u nonexistent_user_xyzzy_42 -b -l 100 /

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
