#!/bin/bash
# check-deps.sh — verify host tools needed by the BSD test framework
#
# Run after git clone to confirm the host is ready for BSD testing.
# Exit 0 = all good. Exit 1 = something required is missing.
#
# Usage:
#   test/bsd/check-deps.sh          # normal check
#   test/bsd/check-deps.sh -v       # verbose (show paths and versions)
set -euo pipefail

# ---------------------------------------------------------------------------
# Detect distro family for install hints
# ---------------------------------------------------------------------------

_distro_family() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "${ID:-}${ID_LIKE:-}" in
            *debian*|*ubuntu*) echo "deb" ; return ;;
            *fedora*|*rhel*|*centos*|*alma*|*rocky*) echo "rpm" ; return ;;
            *suse*|*opensuse*) echo "rpm" ; return ;;
            *arch*) echo "arch" ; return ;;
        esac
    fi
    echo "unknown"
}

DISTRO=$(_distro_family)

# ---------------------------------------------------------------------------
# Check helpers
# ---------------------------------------------------------------------------

VERBOSE=0
[[ "${1:-}" == "-v" || "${1:-}" == "--verbose" ]] && VERBOSE=1

PASS=0
FAIL=0
WARN=0

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' BOLD='' NC=''
fi

_ok() {
    local name="$1"
    local detail="${2:-}"
    PASS=$((PASS + 1))
    if [ "$VERBOSE" -eq 1 ] && [ -n "$detail" ]; then
        printf "  ${GREEN}OK${NC}  %-22s %s\n" "$name" "$detail"
    else
        printf "  ${GREEN}OK${NC}  %s\n" "$name"
    fi
}

_fail() {
    local name="$1"
    local hint="$2"
    FAIL=$((FAIL + 1))
    printf "  ${RED}MISS${NC} %-22s %s\n" "$name" "$hint"
}

_warn() {
    local name="$1"
    local msg="$2"
    WARN=$((WARN + 1))
    printf "  ${YELLOW}WARN${NC} %-22s %s\n" "$name" "$msg"
}

_hint() {
    local deb_pkg="$1"
    local rpm_pkg="${2:-$deb_pkg}"
    local arch_pkg="${3:-$deb_pkg}"
    case "$DISTRO" in
        deb) echo "apt install $deb_pkg" ;;
        rpm) echo "dnf install $rpm_pkg" ;;
        arch) echo "pacman -S $arch_pkg" ;;
        *) echo "install: $deb_pkg" ;;
    esac
}

_check_cmd() {
    local name="$1"
    local cmd="$2"
    local deb_pkg="$3"
    local rpm_pkg="${4:-$deb_pkg}"
    local arch_pkg="${5:-$deb_pkg}"
    local required="${6:-1}"

    if command -v "$cmd" >/dev/null 2>&1; then
        local detail=""
        if [ "$VERBOSE" -eq 1 ]; then
            local path ver
            path=$(command -v "$cmd")
            ver=$("$cmd" --version 2>/dev/null | head -1 || echo "")
            detail="($path)${ver:+ $ver}"
        fi
        _ok "$name" "$detail"
        return 0
    else
        if [ "$required" -eq 1 ]; then
            _fail "$name" "$(_hint "$deb_pkg" "$rpm_pkg" "$arch_pkg")"
        else
            _warn "$name" "not found — $(_hint "$deb_pkg" "$rpm_pkg" "$arch_pkg")"
        fi
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

echo ""
printf "${BOLD}quotatool BSD test framework — dependency check${NC}\n"
echo ""

# --- VM infrastructure ---
printf "${BOLD}VM infrastructure:${NC}\n"

_check_cmd "qemu" "qemu-system-x86_64" \
    "qemu-system-x86" "qemu-system-x86-core" "qemu-system-x86_64"

_check_cmd "qemu-img" "qemu-img" \
    "qemu-utils" "qemu-img" "qemu-img"

# KVM
if [ -e /dev/kvm ]; then
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        _ok "/dev/kvm" ""
    else
        _warn "/dev/kvm" "exists but not accessible — run: sudo usermod -aG kvm \$USER (then re-login)"
    fi
else
    _fail "/dev/kvm" "not available — BSD VMs require KVM for reasonable performance"
fi

echo ""

# --- Image tools ---
printf "${BOLD}Image & provisioning tools:${NC}\n"

_check_cmd "genisoimage" "genisoimage" \
    "genisoimage" "genisoimage" "cdrtools"

_check_cmd "curl" "curl" \
    "curl" "curl" "curl"

_check_cmd "xz" "xz" \
    "xz-utils" "xz" "xz"

echo ""

# --- SSH ---
printf "${BOLD}SSH (file transfer & remote execution):${NC}\n"

_check_cmd "ssh" "ssh" \
    "openssh-client" "openssh-clients" "openssh"

_check_cmd "scp" "scp" \
    "openssh-client" "openssh-clients" "openssh"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf "${BOLD}Summary:${NC} "
if [ "$FAIL" -eq 0 ]; then
    printf "${GREEN}${PASS} OK${NC}"
    if [ "$WARN" -gt 0 ]; then
        printf ", ${YELLOW}${WARN} warnings${NC}"
    fi
    echo ""
    echo "Ready for BSD testing."
    exit 0
else
    printf "${RED}${FAIL} missing${NC}, ${GREEN}${PASS} OK${NC}"
    if [ "$WARN" -gt 0 ]; then
        printf ", ${YELLOW}${WARN} warnings${NC}"
    fi
    echo ""
    echo "Install missing tools before running BSD tests. See test/bsd/DEPENDENCIES.md"
    exit 1
fi
