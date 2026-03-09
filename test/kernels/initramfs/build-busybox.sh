#!/bin/bash
# Obtain a statically-linked busybox for initramfs use.
#
# Output: busybox-musl in the same directory as this script.
#
# Primary: downloads official pre-built musl-static binary from busybox.net.
# Fallback: builds from source (requires musl-tools, build-essential).
#
# The binary is musl-linked (no glibc), truly static (no .so deps),
# and has no minimum kernel version — works on kernels as old as 2.6.32.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/busybox-musl"

# Known-good official binary from busybox.net
BB_URL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
BB_SHA256="6e123e7f3202a8c1e9b1f94d8941580a25135382b99e8d3e34fb858bba311348"

verify() {
    local file="$1"
    if ! file "$file" | grep -q 'statically linked'; then
        echo "ERROR: $file is not statically linked" >&2
        return 1
    fi
    if ! file "$file" | grep -q 'ELF 64-bit'; then
        echo "ERROR: $file is not a 64-bit ELF binary" >&2
        return 1
    fi
    return 0
}

# --- Primary: download official binary ---
download_official() {
    echo "Downloading official busybox (musl-static) from busybox.net..."
    local tmp
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' RETURN

    if ! curl -fsSL -o "$tmp" "$BB_URL"; then
        echo "Download failed" >&2
        return 1
    fi

    # Verify checksum
    local got
    got=$(sha256sum "$tmp" | cut -d' ' -f1)
    if [ "$got" != "$BB_SHA256" ]; then
        echo "SHA256 mismatch: expected $BB_SHA256, got $got" >&2
        return 1
    fi

    chmod +x "$tmp"
    if ! verify "$tmp"; then
        return 1
    fi

    mv "$tmp" "$OUTPUT"
    local applets
    applets=$("$OUTPUT" --list 2>/dev/null | wc -l)
    echo "OK: $OUTPUT ($(du -h "$OUTPUT" | cut -f1), $applets applets, sha256 verified)"
}

# --- Fallback: build from source ---
build_from_source() {
    echo "Falling back to building from source..."
    local BB_VERSION=1.36.1

    if ! command -v musl-gcc >/dev/null 2>&1; then
        echo "ERROR: musl-gcc not found. Install musl-tools:" >&2
        echo "  sudo apt install musl-tools" >&2
        return 1
    fi

    local work
    work=$(mktemp -d)
    trap 'rm -rf "$work"' RETURN

    echo "Downloading busybox $BB_VERSION source..."
    curl -sL "https://busybox.net/downloads/busybox-${BB_VERSION}.tar.bz2" | tar xj -C "$work"
    cd "$work/busybox-${BB_VERSION}"

    # allnoconfig + enable only what initramfs needs
    make allnoconfig >/dev/null 2>&1
    local enable_list=(
        CONFIG_STATIC
        CONFIG_ASH CONFIG_ASH_BASH_COMPAT CONFIG_ASH_TEST
        CONFIG_FEATURE_SH_MATH CONFIG_FEATURE_SH_MATH_64
        CONFIG_CAT CONFIG_ECHO CONFIG_MKDIR CONFIG_TEST CONFIG_TRUE
        CONFIG_FALSE CONFIG_SLEEP CONFIG_READLINK CONFIG_CHMOD
        CONFIG_CP CONFIG_LN CONFIG_LS CONFIG_MV CONFIG_RM
        CONFIG_MKNOD CONFIG_DD CONFIG_SYNC CONFIG_GREP CONFIG_SED
        CONFIG_MOUNT CONFIG_UMOUNT CONFIG_FEATURE_MOUNT_FLAGS
        CONFIG_FEATURE_MOUNT_VERBOSE CONFIG_LOSETUP CONFIG_CHROOT
        CONFIG_SWITCH_ROOT CONFIG_INSMOD CONFIG_POWEROFF
    )
    for opt in "${enable_list[@]}"; do
        sed -i "s/# $opt is not set/$opt=y/" .config
    done
    yes '' | make oldconfig >/dev/null 2>&1

    if ! grep -q 'CONFIG_STATIC=y' .config; then
        echo "FATAL: CONFIG_STATIC got cleared by oldconfig" >&2
        return 1
    fi

    echo "Building busybox $BB_VERSION with musl-gcc..."
    if ! make CC=musl-gcc -j"$(nproc)" >build.log 2>&1; then
        echo "Build failed:" >&2
        grep -iE '(error|fatal)' build.log | head -10 >&2
        return 1
    fi

    cp busybox "$OUTPUT"
    chmod +x "$OUTPUT"
    echo "OK: $OUTPUT ($(du -h "$OUTPUT" | cut -f1) — built from source)"
}

# --- Main ---
if [ -f "$OUTPUT" ] && [ "${1:-}" != "--force" ]; then
    echo "busybox-musl already exists ($(du -h "$OUTPUT" | cut -f1)). Use --force to rebuild."
    exit 0
fi

if download_official; then
    exit 0
fi

echo ""
echo "Official download failed, trying source build..."
if build_from_source; then
    exit 0
fi

echo ""
echo "FAILED: could not obtain static busybox" >&2
exit 1
