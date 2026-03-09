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
    # Handles symlink chains: copies the source as-is (preserving symlinks),
    # then walks the chain copying each intermediate link AND the final
    # resolved target. Uses both one-hop readlink AND readlink -f to
    # ensure nothing is missed.
    local src="$1" dst_root="$2"
    local dest="$dst_root$src"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest" 2>/dev/null || true

    # Walk symlink chain one hop at a time (catches intermediates)
    local cur="$src"
    while [[ -L "$cur" ]]; do
        local raw_target
        raw_target=$(readlink "$cur")
        local abs_target
        if [[ "$raw_target" == /* ]]; then
            abs_target="$raw_target"
        else
            abs_target="$(dirname "$cur")/$raw_target"
        fi
        if [[ -e "$abs_target" || -L "$abs_target" ]]; then
            local dest_target="$dst_root$abs_target"
            mkdir -p "$(dirname "$dest_target")"
            cp -a "$abs_target" "$dest_target" 2>/dev/null || true
        fi
        cur="$abs_target"
    done

    # Also copy the fully resolved target (readlink -f skips to end)
    if [[ -L "$src" ]]; then
        local final
        final=$(readlink -f "$src" 2>/dev/null || true)
        if [[ -n "$final" && -e "$final" ]]; then
            local dest_final="$dst_root$final"
            mkdir -p "$(dirname "$dest_final")"
            cp -a "$final" "$dest_final" 2>/dev/null || true
        fi
    fi
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

# Create directory structure — mirror host's merged-usr layout if present.
# Modern distros (Debian 12+, Fedora 17+, Ubuntu 20.04+) merge /bin→/usr/bin,
# /lib→/usr/lib, etc. Compiled-in paths (e.g., PAM module dir) reference the
# non-canonical path, so the rootfs must have matching symlinks.
mkdir -p "$STAGING"/usr/{bin,sbin,lib,lib64}
mkdir -p "$STAGING"/{etc,dev,proc,sys,tmp,run,var/tmp,root}
mkdir -p "$STAGING/dev/pts"
for _d in bin sbin lib lib64; do
    if [[ -L "/$_d" ]]; then
        # Host has merged-usr: create matching symlink
        ln -sf "$(readlink "/$_d")" "$STAGING/$_d"
    else
        mkdir -p "$STAGING/$_d"
    fi
done
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

# Copy the dynamic linker — discover it, don't hardcode paths.
# The linker is whatever the ELF INTERP header of /bin/sh points to.
_interp=$(readelf -l "$(readlink -f /bin/sh)" 2>/dev/null \
    | grep -oP '(?<=interpreter: )\S+(?=\])' || true)
if [[ -n "$_interp" && -e "$_interp" ]]; then
    copy_with_path "$_interp" "$STAGING"
    # Some binaries reference /lib64/ld-linux-x86-64.so.2 regardless
    # of where it actually lives. Ensure that path works too.
    if [[ "$_interp" != /lib64/* && ! -e "$STAGING/lib64/$(basename "$_interp")" ]]; then
        # lib64 may be a symlink (merged-usr) or dir — handle both
        if [[ -L "$STAGING/lib64" ]]; then
            # Symlink: target dir should already exist under /usr/lib64
            mkdir -p "$STAGING/usr/lib64" 2>/dev/null || true
        elif [[ ! -d "$STAGING/lib64" ]]; then
            mkdir -p "$STAGING/lib64"
        fi
        ln -sf "$_interp" "$STAGING/lib64/$(basename "$_interp")"
    fi
fi

# PAM modules (needed by runuser for privilege switching in tests)
log "Copying PAM modules and config..."
# Discover PAM security dir dynamically — find where pam_permit.so lives
pam_security=""
_pam_permit=$(find /lib /lib64 /usr/lib /usr/lib64 -name "pam_permit.so" 2>/dev/null | head -1 || true)
if [[ -n "$_pam_permit" ]]; then
    pam_security=$(dirname "$_pam_permit")
fi
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

# Generate ld.so.conf from the actual library directories in staging
# (no hardcoded paths — works on Debian, Fedora, Arch, etc.)
: > "$STAGING/etc/ld.so.conf"
for _dir in $(find "$STAGING" -name "*.so*" -printf '%h\n' 2>/dev/null | sort -u); do
    # Strip staging prefix to get the path as seen inside the rootfs
    _reldir="${_dir#"$STAGING"}"
    [[ -n "$_reldir" ]] && echo "$_reldir" >> "$STAGING/etc/ld.so.conf"
done

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
