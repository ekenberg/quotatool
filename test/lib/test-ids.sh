#!/bin/bash
# test-ids.sh — discover portable user/group IDs for testing
#
# Source this file to get test identity variables.
# Pure bash — reads /etc/passwd and /etc/group directly, no external tools.
#
# Exports:
#   TEST_USER_NAME    — existing non-root user name (for quotatool -u <name>)
#   TEST_USER_UID     — its numeric uid (for quotatool -u <uid>)
#   TEST_GROUP_NAME   — existing non-root group name (for quotatool -g <name>)
#   TEST_GROUP_GID    — its numeric gid (for quotatool -g <gid>)
#   TEST_NOEXIST_UID  — a uid NOT in /etc/passwd (for quotatool -u :<uid>)
#   TEST_NOEXIST_GID  — a gid NOT in /etc/group (for quotatool -g :<gid>)

# --- Find existing user ---
# Prefer "nobody" (universal, uid 65534). Fall back to first non-root.
_find_test_user() {
    local name x uid
    # First pass: look for nobody
    while IFS=: read -r name x uid _; do
        if [[ "$name" == "nobody" ]]; then
            echo "$name $uid"
            return
        fi
    done < /etc/passwd
    # Second pass: first non-root user
    while IFS=: read -r name x uid _; do
        if [[ "$uid" -gt 0 ]]; then
            echo "$name $uid"
            return
        fi
    done < /etc/passwd
    echo "NONE 0"
}

# --- Find existing group ---
# Prefer "nogroup" (Debian/Ubuntu), then "nobody" (Fedora/RHEL).
# Fall back to first non-root group.
_find_test_group() {
    local name x gid target
    for target in nogroup nobody; do
        while IFS=: read -r name x gid _; do
            if [[ "$name" == "$target" ]]; then
                echo "$name $gid"
                return
            fi
        done < /etc/group
    done
    # Fall back: first non-root group
    while IFS=: read -r name x gid _; do
        if [[ "$gid" -gt 0 ]]; then
            echo "$name $gid"
            return
        fi
    done < /etc/group
    echo "NONE 0"
}

# --- Find non-existent uid ---
# Collect all existing uids, then scan from 1025 up for the first gap.
_find_noexist_uid() {
    local name x uid
    local -A existing=()
    while IFS=: read -r name x uid _; do
        existing[$uid]=1
    done < /etc/passwd
    local candidate=1025
    while [[ -n "${existing[$candidate]+x}" ]]; do
        ((candidate++))
    done
    echo "$candidate"
}

# --- Find non-existent gid ---
_find_noexist_gid() {
    local name x gid
    local -A existing=()
    while IFS=: read -r name x gid _; do
        existing[$gid]=1
    done < /etc/group
    local candidate=1025
    while [[ -n "${existing[$candidate]+x}" ]]; do
        ((candidate++))
    done
    echo "$candidate"
}

# --- Resolve and export ---
read -r TEST_USER_NAME TEST_USER_UID <<< "$(_find_test_user)"
read -r TEST_GROUP_NAME TEST_GROUP_GID <<< "$(_find_test_group)"
TEST_NOEXIST_UID=$(_find_noexist_uid)
TEST_NOEXIST_GID=$(_find_noexist_gid)

export TEST_USER_NAME TEST_USER_UID
export TEST_GROUP_NAME TEST_GROUP_GID
export TEST_NOEXIST_UID TEST_NOEXIST_GID
