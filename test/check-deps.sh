#!/bin/bash
# check-deps.sh — verify all host tools needed by the test framework
#
# Run after git clone to confirm the host is ready for testing.
# Exit 0 = all good. Exit 1 = something required is missing.
#
# Usage:
#   test/check-deps.sh          # normal check
#   test/check-deps.sh -v       # verbose (show paths and versions)
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

# Install hint for a package, adapted to distro
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

# Check that a command exists. Optionally show version.
_check_cmd() {
    local name="$1"
    local cmd="$2"
    local deb_pkg="$3"
    local rpm_pkg="${4:-$deb_pkg}"
    local arch_pkg="${5:-$deb_pkg}"
    local required="${6:-1}"  # 1=required, 0=optional

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
printf "${BOLD}quotatool test framework — dependency check${NC}\n"
echo ""

# --- VM infrastructure ---
printf "${BOLD}VM infrastructure:${NC}\n"

_check_cmd "qemu" "qemu-system-x86_64" \
    "qemu-system-x86" "qemu-system-x86-core" "qemu-system-x86_64"

_check_cmd "virtme-ng (vng)" "vng" \
    "virtme-ng (pip install virtme-ng)" "virtme-ng (pip install virtme-ng)" "virtme-ng (pip install virtme-ng)"


# KVM
if [ -e /dev/kvm ]; then
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        _ok "/dev/kvm" ""
    else
        _warn "/dev/kvm" "exists but not accessible — run: sudo usermod -aG kvm \$USER (then re-login)"
    fi
else
    _warn "/dev/kvm" "not available — VMs will use emulation (very slow)"
fi

echo ""

# --- Filesystem tools ---
printf "${BOLD}Filesystem & quota tools:${NC}\n"

_check_cmd "mkfs.ext4" "mkfs.ext4" \
    "e2fsprogs" "e2fsprogs" "e2fsprogs"

_check_cmd "mkfs.xfs" "mkfs.xfs" \
    "xfsprogs" "xfsprogs" "xfsprogs"

_check_cmd "quotaon" "quotaon" \
    "quota" "quota" "quota-tools"

_check_cmd "quotacheck" "quotacheck" \
    "quota" "quota" "quota-tools"

_check_cmd "repquota" "repquota" \
    "quota" "quota" "quota-tools"

_check_cmd "losetup" "losetup" \
    "util-linux" "util-linux" "util-linux"

_check_cmd "truncate" "truncate" \
    "coreutils" "coreutils" "coreutils"

echo ""

# --- Kernel package extraction ---
printf "${BOLD}Kernel package extraction:${NC}\n"

_check_cmd "cpio" "cpio" \
    "cpio" "cpio" "cpio"

_check_cmd "rpm2cpio" "rpm2cpio" \
    "rpm2cpio" "rpm" "rpm-tools" 0

_check_cmd "dpkg-deb" "dpkg-deb" \
    "dpkg" "dpkg" "dpkg"

echo ""

# --- Download & build tools ---
printf "${BOLD}Download & build tools:${NC}\n"

_check_cmd "curl" "curl" \
    "curl" "curl" "curl"

_check_cmd "gzip" "gzip" \
    "gzip" "gzip" "gzip"

# xz and zstd: needed for decompressing RHEL .ko.xz/.ko.zst modules
_check_cmd "xz" "xz" \
    "xz-utils" "xz" "xz" 0

_check_cmd "zstd" "zstd" \
    "zstd" "zstd" "zstd" 0

# modinfo: needed for resolving kernel module dependencies
_check_cmd "modinfo" "modinfo" \
    "kmod" "kmod" "kmod"

# file: used to verify binaries (static linking check)
_check_cmd "file" "file" \
    "file" "file" "file"

echo ""

# --- Initramfs ---
printf "${BOLD}Initramfs:${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BB="$SCRIPT_DIR/kernels/initramfs/busybox-musl"
INITRAMFS="$SCRIPT_DIR/kernels/initramfs/initramfs.cpio.gz"

if [ -f "$BB" ]; then
    if file "$BB" | grep -q 'statically linked'; then
        _ok "busybox-musl" "(static, $(du -h "$BB" | cut -f1))"
    else
        _warn "busybox-musl" "exists but NOT statically linked — run: test/kernels/initramfs/build-busybox.sh --force"
    fi
else
    _warn "busybox-musl" "not found — will be downloaded by run-tests --setup"
fi

if [ -f "$INITRAMFS" ]; then
    _ok "initramfs.cpio.gz" "($(du -h "$INITRAMFS" | cut -f1))"
else
    _warn "initramfs.cpio.gz" "not built — will be built by run-tests --setup"
fi

echo ""

# --- Alpine rootfs build (for RHEL/old kernels) ---
printf "${BOLD}Alpine rootfs build (for RHEL/old kernels):${NC}\n"

_check_cmd "musl-gcc" "musl-gcc" \
    "musl-tools" "musl-gcc (dnf install musl-tools or musl-gcc)" "musl" 0

# asm/types.h: needed by kernel UAPI headers during static musl build
# Location varies: /usr/include/asm (Fedora) or multiarch (Debian/Ubuntu)
if [ -d /usr/include/asm ] || [ -d "/usr/include/$(gcc -dumpmachine 2>/dev/null)/asm" ]; then
    _ok "asm headers" ""
else
    _warn "asm headers" "not found — $(_hint "linux-libc-dev" "kernel-headers" "linux-api-headers")"
fi

echo ""

# --- quotatool binary ---
printf "${BOLD}Project:${NC}\n"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QT="$PROJECT_DIR/quotatool"

if [ -x "$QT" ]; then
    _ok "quotatool binary" "($QT)"
else
    _warn "quotatool" "not built — run: ./configure && make"
fi

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
    echo "Ready to run tests."
    exit 0
else
    printf "${RED}${FAIL} missing${NC}, ${GREEN}${PASS} OK${NC}"
    if [ "$WARN" -gt 0 ]; then
        printf ", ${YELLOW}${WARN} warnings${NC}"
    fi
    echo ""
    echo "Install missing required tools before running tests."
    exit 1
fi
