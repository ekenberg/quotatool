#!/bin/bash
# build-rootfs.sh — Build a minimal rootfs disk image for RHEL kernel testing
#
# Creates a self-contained ext4 disk image containing:
# - Host binaries needed by the test suite (bash, mkfs, quota tools, etc.)
# - Their shared library dependencies
# - The test scripts and quotatool binary
# - Minimal /etc for user lookup (nobody, root)
#
# This image is used instead of 9p for kernels that lack 9p.ko
# (all RHEL-derived: centos6/7, alma8/9/10, amazon-2).
#
# The image is NOT stored in git. Rebuild with: ./build-rootfs.sh
# One image works for all RHEL kernels (kernel is passed separately).
#
# No sudo required — uses mkfs.ext4 -d to populate from a directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$TEST_DIR")"
ROOTFS_IMG="$SCRIPT_DIR/rootfs.img"
ROOTFS_SIZE="512M"

# ---------------------------------------------------------------------------
# Binaries the test suite needs inside the VM
# ---------------------------------------------------------------------------

BINS=(
    # Shell
    bash sh
    # Coreutils
    cat chmod chown cp cut dd dirname basename echo false head
    id ln ls mkdir mktemp mv printf pwd readlink realpath rm
    sed sleep sort tail test touch tr true truncate uniq wc uname
    # Findutils / grep / awk
    find grep xargs awk gawk
    # Coreutils extras (seq used in tests, date/expr sometimes needed)
    seq expr date
    # Filesystem tools
    mkfs.ext4 mke2fs mkfs.xfs
    mount umount losetup dumpe2fs
    # Quota tools
    quotacheck quotaon quotaoff repquota
    # Misc system
    runuser modprobe insmod poweroff env
    # ldconfig (for library resolution inside rootfs)
    ldconfig
)

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

log() { echo "rootfs: $*"; }
err() { echo "rootfs: ERROR: $*" >&2; }

resolve_bin() {
    # Find the absolute path of a binary
    local name="$1"
    local p
    p=$(which "$name" 2>/dev/null) && echo "$p" && return 0
    for dir in /bin /sbin /usr/bin /usr/sbin; do
        [[ -f "$dir/$name" ]] && echo "$dir/$name" && return 0
    done
    return 1
}

collect_libs() {
    # Collect all shared library dependencies for a list of binary paths
    for bin in "$@"; do
        ldd "$bin" 2>/dev/null | grep -oE '/[^ ]+' || true
    done | sort -u
}

copy_with_path() {
    # Copy a file into staging dir, preserving its absolute path.
    # Follows the full symlink chain (e.g., awk → alternatives → gawk).
    local src="$1" dst_root="$2"
    local dest="$dst_root$src"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest" 2>/dev/null || true
    # Walk the full symlink chain and copy each intermediate target
    local cur="$src"
    while [[ -L "$cur" ]]; do
        local link_target
        link_target=$(readlink "$cur")
        # Handle relative symlinks
        if [[ "$link_target" != /* ]]; then
            link_target="$(dirname "$cur")/$link_target"
        fi
        # Normalize
        link_target=$(readlink -f "$link_target" 2>/dev/null || echo "$link_target")
        if [[ -e "$link_target" ]]; then
            local dest_target="$dst_root$link_target"
            mkdir -p "$(dirname "$dest_target")"
            cp -a "$link_target" "$dest_target" 2>/dev/null || true
        fi
        cur="$link_target"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [[ -f "$ROOTFS_IMG" ]]; then
    log "rootfs.img already exists ($(du -h "$ROOTFS_IMG" | cut -f1))"
    log "Use --force to rebuild"
    if [[ "${1:-}" != "--force" ]]; then
        exit 0
    fi
    log "Rebuilding..."
    rm -f "$ROOTFS_IMG"
fi

# Check that quotatool is built
QUOTATOOL="$PROJECT_DIR/quotatool"
if [[ ! -x "$QUOTATOOL" ]]; then
    log "Building quotatool first..."
    make -C "$PROJECT_DIR" -j"$(nproc)" >/dev/null 2>&1 \
        || { err "quotatool build failed"; exit 1; }
fi

# Resolve all binary paths
log "Resolving binary paths..."
resolved_bins=()
missing=()
for name in "${BINS[@]}"; do
    p=$(resolve_bin "$name") || true
    if [[ -n "$p" ]]; then
        resolved_bins+=("$p")
    else
        missing+=("$name")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing binaries: ${missing[*]}"
    err "Install the required packages and retry."
    exit 1
fi
log "  ${#resolved_bins[@]} binaries found"

# Collect shared libraries
log "Collecting shared library dependencies..."
mapfile -t libs < <(collect_libs "${resolved_bins[@]}")
log "  ${#libs[@]} unique shared libraries"

# Build staging directory
STAGING=$(mktemp -d /tmp/rootfs-staging.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT

log "Building staging directory..."

# Create directory structure
mkdir -p "$STAGING"/{bin,sbin,lib,lib64,usr/bin,usr/sbin,usr/lib,usr/lib64}
mkdir -p "$STAGING"/{etc,dev,proc,sys,tmp,run,var/tmp,root}
mkdir -p "$STAGING/dev/pts"
chmod 1777 "$STAGING/tmp" "$STAGING/var/tmp"

# Copy binaries
for bin in "${resolved_bins[@]}"; do
    copy_with_path "$bin" "$STAGING"
done

# Ensure /bin/sh exists
if [[ ! -e "$STAGING/bin/sh" ]]; then
    ln -sf bash "$STAGING/bin/sh"
fi

# Fix alternatives symlinks: create direct links for commands that go
# through /etc/alternatives/ (awk → alternatives → gawk, etc.)
for bin in "${resolved_bins[@]}"; do
    real=$(readlink -f "$bin")
    name=$(basename "$bin")
    # If the real target differs from the symlink, ensure a direct path works
    if [[ "$real" != "$bin" && -f "$real" ]]; then
        # Ensure the binary name works in /usr/bin
        if [[ ! -e "$STAGING/usr/bin/$name" ]]; then
            ln -sf "$real" "$STAGING/usr/bin/$name"
        fi
    fi
done

# Copy shared libraries
for lib in "${libs[@]}"; do
    copy_with_path "$lib" "$STAGING"
done

# Copy the dynamic linker(s)
for ld in /lib64/ld-linux-x86-64.so* /lib/x86_64-linux-gnu/ld-linux-x86-64.so*; do
    [[ -f "$ld" || -L "$ld" ]] && copy_with_path "$ld" "$STAGING"
done

# Ensure /lib64 exists (some binaries hardcode it)
if [[ -d "$STAGING/lib/x86_64-linux-gnu" && ! -e "$STAGING/lib64" ]]; then
    ln -sf lib/x86_64-linux-gnu "$STAGING/lib64"
elif [[ ! -e "$STAGING/lib64" ]]; then
    mkdir -p "$STAGING/lib64"
fi

# PAM modules (needed by runuser for privilege switching in tests)
log "Copying PAM modules and config..."
pam_security=""
for d in /lib/x86_64-linux-gnu/security /lib64/security /usr/lib/x86_64-linux-gnu/security; do
    if [[ -d "$d" ]]; then
        pam_security="$d"
        break
    fi
done
if [[ -n "$pam_security" ]]; then
    mkdir -p "$STAGING$pam_security"
    cp -a "$pam_security"/*.so "$STAGING$pam_security/" 2>/dev/null || true
    # PAM module library deps
    mapfile -t pam_libs < <(collect_libs "$pam_security"/*.so 2>/dev/null)
    for lib in "${pam_libs[@]}"; do
        copy_with_path "$lib" "$STAGING"
    done
fi
# Minimal PAM config (host's config references systemd/loginuid which fail in chroot)
mkdir -p "$STAGING/etc/pam.d"
for svc in runuser runuser-l su su-l other; do
    cat > "$STAGING/etc/pam.d/$svc" <<'PAM'
auth    sufficient  pam_rootok.so
auth    sufficient  pam_permit.so
account sufficient  pam_permit.so
session sufficient  pam_permit.so
PAM
done

# Minimal /etc
cat > "$STAGING/etc/passwd" <<'PASSWD'
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
PASSWD

cat > "$STAGING/etc/group" <<'GROUP'
root:x:0:
nogroup:x:65534:
GROUP

cat > "$STAGING/etc/nsswitch.conf" <<'NSS'
passwd: files
group: files
shadow: files
NSS

# /etc/mtab symlink (some mount implementations need it)
ln -sf /proc/mounts "$STAGING/etc/mtab"

# login.defs (runuser reads it)
[[ -f /etc/login.defs ]] && cp /etc/login.defs "$STAGING/etc/login.defs"

cat > "$STAGING/etc/ld.so.conf" <<'LDCONF'
/lib
/lib64
/usr/lib
/usr/lib64
/lib/x86_64-linux-gnu
/usr/lib/x86_64-linux-gnu
LDCONF

# Run ldconfig in staging to generate ld.so.cache
if [[ -x "$STAGING/sbin/ldconfig" ]]; then
    # ldconfig can run with -r to use an alternate root
    "$STAGING/sbin/ldconfig" -r "$STAGING" 2>/dev/null || true
fi

# Copy quotatool binary
cp -a "$QUOTATOOL" "$STAGING/usr/bin/quotatool"

# Copy test scripts
mkdir -p "$STAGING/test"
cp -a "$TEST_DIR/guest-run-all.sh" "$STAGING/test/"
cp -a "$TEST_DIR/lib" "$STAGING/test/"
cp -a "$TEST_DIR/tests" "$STAGING/test/"
# Symlink so test scripts find quotatool at ../../quotatool (relative to tests/)
# guest-run-all.sh uses $SCRIPT_DIR which will be /test
# t-*.sh uses $SCRIPT_DIR/../../quotatool → /quotatool
ln -sf /usr/bin/quotatool "$STAGING/quotatool"
# Also create the expected relative path from tests/
mkdir -p "$STAGING/src"
ln -sf /usr/bin/quotatool "$STAGING/src/quotatool"

# Create the ext4 image from the staging directory (no sudo needed!)
log "Creating ext4 image from staging directory..."
# mke2fs -d populates the filesystem from a directory tree
mke2fs -q -t ext4 -O ^metadata_csum \
    -d "$STAGING" \
    "$ROOTFS_IMG" \
    "$ROOTFS_SIZE" 2>&1 | grep -v '^$' || true

img_size=$(du -h "$ROOTFS_IMG" | cut -f1)
staging_size=$(du -sh "$STAGING" | cut -f1)
log "rootfs.img built successfully ($img_size, content $staging_size)"
log "Contains: ${#resolved_bins[@]} binaries, ${#libs[@]} libraries, test suite, quotatool"
