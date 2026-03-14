#!/bin/bash
# build-alpine-rootfs.sh — Build a musl-based rootfs for old/RHEL kernel testing
#
# Creates a self-contained Alpine Linux rootfs disk image containing:
# - Alpine minirootfs (musl-based, no kernel version floor)
# - Test tool packages (bash, e2fsprogs, xfsprogs, quota-tools, util-linux)
# - Static musl-linked quotatool (our code under test)
# - Test scripts
#
# This replaces the host-dependent rootfs (build-rootfs.sh) with a
# host-independent one. musl libc has no minimum kernel version, so
# this rootfs works on ANY kernel — including those below the host's
# glibc floor.
#
# Use cases:
# - Kernels below host glibc floor (e.g., 3.2 on glibc 2.40+ host)
# - RHEL kernels without 9p (alma/centos — no host filesystem sharing)
#
# No sudo required — uses apk.static + fakeroot + mke2fs -d.
#
# Output: alpine-rootfs.img in the same directory as this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$TEST_DIR")"
ROOTFS_IMG="$SCRIPT_DIR/alpine-rootfs.img"
ROOTFS_SIZE="256M"

# ---------------------------------------------------------------------------
# Alpine Linux minirootfs — pinned version + checksum
# ---------------------------------------------------------------------------

ALPINE_VERSION="3.23.3"
ALPINE_BRANCH="v3.23"
ALPINE_ARCH="x86_64"
ALPINE_TARBALL="alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/${ALPINE_BRANCH}/releases/${ALPINE_ARCH}/${ALPINE_TARBALL}"
ALPINE_SHA256="42d0e6d8de5521e7bf92e075e032b5690c1d948fa9775efa32a51a38b25460fb"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"

# Where we cache the downloaded tarball
ALPINE_CACHE="$SCRIPT_DIR/.alpine-cache"

# Packages to install into the rootfs
ALPINE_PACKAGES=(
    bash
    e2fsprogs           # mkfs.ext4, dumpe2fs
    e2fsprogs-extra     # quota support for ext4
    xfsprogs            # mkfs.xfs
    quota-tools         # quotacheck, quotaon, quotaoff, repquota
    util-linux          # mount, umount, losetup, runuser, setpriv
    util-linux-misc     # runuser is here on Alpine
    coreutils           # full coreutils (Alpine default is busybox)
    grep                # full grep
    sed                 # full sed
    findutils           # find
    linux-pam           # needed by runuser
)

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

log() { echo "alpine-rootfs: $*"; }
err() { echo "alpine-rootfs: ERROR: $*" >&2; }

# Download Alpine minirootfs tarball (cached).
# Sets ALPINE_TARBALL_PATH on success.
download_alpine() {
    mkdir -p "$ALPINE_CACHE"
    ALPINE_TARBALL_PATH="$ALPINE_CACHE/$ALPINE_TARBALL"

    if [[ -f "$ALPINE_TARBALL_PATH" ]]; then
        local got
        got=$(sha256sum "$ALPINE_TARBALL_PATH" | cut -d' ' -f1)
        if [[ "$got" == "$ALPINE_SHA256" ]]; then
            log "Using cached Alpine minirootfs ($ALPINE_VERSION)"
            return 0
        fi
        log "Cached tarball has wrong checksum, re-downloading..."
        rm -f "$ALPINE_TARBALL_PATH"
    fi

    log "Downloading Alpine minirootfs $ALPINE_VERSION..."
    if ! curl -fsSL -o "$ALPINE_TARBALL_PATH" "$ALPINE_URL"; then
        err "Download failed: $ALPINE_URL"
        return 1
    fi

    local got
    got=$(sha256sum "$ALPINE_TARBALL_PATH" | cut -d' ' -f1)
    if [[ "$got" != "$ALPINE_SHA256" ]]; then
        err "SHA256 mismatch: expected $ALPINE_SHA256, got $got"
        rm -f "$ALPINE_TARBALL_PATH"
        return 1
    fi

    log "Download OK (SHA256 verified)"
}

# Download apk.static from Alpine (needed to install packages without root).
# Sets APK_STATIC_PATH on success.
download_apk_static() {
    APK_STATIC_PATH="$ALPINE_CACHE/apk.static"

    if [[ -x "$APK_STATIC_PATH" ]]; then
        return 0
    fi

    log "Downloading apk.static..."
    local apk_url="${ALPINE_MIRROR}/${ALPINE_BRANCH}/main/${ALPINE_ARCH}/"

    # Find the apk-tools-static package URL
    local pkg_name
    pkg_name=$(curl -fsSL "$apk_url" | grep -oP 'apk-tools-static-[^"]+\.apk' | head -1)
    if [[ -z "$pkg_name" ]]; then
        err "Could not find apk-tools-static package"
        return 1
    fi

    local tmp
    tmp=$(mktemp -d)

    if ! curl -fsSL -o "$tmp/apk-tools-static.apk" "${apk_url}${pkg_name}"; then
        err "Failed to download apk-tools-static"
        rm -rf "$tmp"
        return 1
    fi

    # APK files are gzipped tar archives
    tar xzf "$tmp/apk-tools-static.apk" -C "$tmp" sbin/apk.static 2>/dev/null || true
    if [[ ! -f "$tmp/sbin/apk.static" ]]; then
        err "apk.static not found in package"
        rm -rf "$tmp"
        return 1
    fi

    cp "$tmp/sbin/apk.static" "$APK_STATIC_PATH"
    chmod +x "$APK_STATIC_PATH"
    rm -rf "$tmp"
    log "apk.static ready"
}

# Build static musl quotatool
build_static_quotatool() {
    local output="$1"

    if ! command -v musl-gcc >/dev/null 2>&1; then
        err "musl-gcc not found. Install: musl-tools (Debian/Ubuntu) or musl-gcc (Fedora)"
        return 1
    fi

    log "Building static musl quotatool..."

    # Create isolated kernel UAPI headers (avoid glibc contamination)
    local kinclude
    kinclude=$(mktemp -d)

    cp -r /usr/include/linux "$kinclude/linux"
    cp -r /usr/include/asm-generic "$kinclude/asm-generic"
    # asm/ location varies: /usr/include/asm (Fedora) or multiarch (Debian)
    if [[ -d /usr/include/asm ]]; then
        cp -r /usr/include/asm "$kinclude/asm"
    elif [[ -d "/usr/include/$(gcc -dumpmachine)/asm" ]]; then
        cp -r "/usr/include/$(gcc -dumpmachine)/asm" "$kinclude/asm"
    else
        err "Cannot find asm/ headers"
        rm -rf "$kinclude"
        return 1
    fi

    # musl doesn't have sys/cdefs.h (glibc-ism). quotatool's linux_quota.h
    # includes it but uses nothing from it. Provide empty stub.
    mkdir -p "$kinclude/sys"
    echo "/* stub: musl lacks sys/cdefs.h */" > "$kinclude/sys/cdefs.h"

    # Ensure config.h exists (from normal ./configure)
    if [[ ! -f "$PROJECT_DIR/config.h" ]]; then
        log "Running ./configure first (needed for config.h)..."
        (cd "$PROJECT_DIR" && ./configure --quiet) 2>&1
    fi

    # Build with musl-gcc, reusing existing config.h
    # Save and restore original objects
    local obj_backup
    obj_backup=$(mktemp -d)
    cp "$PROJECT_DIR"/src/*.o "$obj_backup/" 2>/dev/null || true
    cp "$PROJECT_DIR"/src/linux/*.o "$obj_backup/" 2>/dev/null || true
    local had_binary=0
    [[ -f "$PROJECT_DIR/quotatool" ]] && had_binary=1

    # Clean objects only
    rm -f "$PROJECT_DIR"/src/*.o "$PROJECT_DIR"/src/linux/*.o "$PROJECT_DIR/quotatool"

    local rc=0
    make -C "$PROJECT_DIR" CC=musl-gcc CFLAGS="-static -I$kinclude" \
        -j"$(nproc)" 2>&1 || rc=$?

    if [[ $rc -eq 0 ]]; then
        cp "$PROJECT_DIR/quotatool" "$output"
        log "Static quotatool built ($(du -h "$output" | cut -f1))"
    else
        err "Static quotatool build failed"
    fi

    # Restore original objects and binary
    rm -f "$PROJECT_DIR"/src/*.o "$PROJECT_DIR"/src/linux/*.o "$PROJECT_DIR/quotatool"
    cp "$obj_backup"/*.o "$PROJECT_DIR/src/" 2>/dev/null || true
    # Rebuild normal binary
    make -C "$PROJECT_DIR" -j"$(nproc)" >/dev/null 2>&1 || true

    rm -rf "$kinclude" "$obj_backup"
    return $rc
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [[ -f "$ROOTFS_IMG" && "${1:-}" != "--force" ]]; then
    log "alpine-rootfs.img already exists ($(du -h "$ROOTFS_IMG" | cut -f1))"
    log "Use --force to rebuild"
    exit 0
fi
[[ -f "$ROOTFS_IMG" ]] && rm -f "$ROOTFS_IMG"

# Step 1: Download Alpine minirootfs
download_alpine || exit 1

# Step 2: Get apk.static
download_apk_static || exit 1

# Step 3: Build static quotatool
static_qt=$(mktemp)
trap "rm -f '$static_qt'" EXIT
build_static_quotatool "$static_qt" || exit 1

# Step 4: Create staging directory
STAGING=$(mktemp -d /tmp/alpine-rootfs-staging.XXXXXX)
trap "rm -rf '$STAGING' '$static_qt'" EXIT

log "Extracting Alpine minirootfs..."
tar xzf "$ALPINE_TARBALL_PATH" -C "$STAGING"

# Step 5: Install packages using fakeroot + apk.static
log "Installing packages..."

# Set up Alpine repositories
mkdir -p "$STAGING/etc/apk"
echo "${ALPINE_MIRROR}/${ALPINE_BRANCH}/main" > "$STAGING/etc/apk/repositories"
echo "${ALPINE_MIRROR}/${ALPINE_BRANCH}/community" >> "$STAGING/etc/apk/repositories"

# Copy host's resolv.conf for DNS during package install
cp /etc/resolv.conf "$STAGING/etc/resolv.conf" 2>/dev/null || true

# Initialize apk database and install packages
# Use fakeroot to avoid permission issues (chown, mknod)
# apk v3 (Alpine 3.23+) supports --usermode: skips chown, runs as non-root.
# fakeroot not needed — apk.static handles it natively.
"$APK_STATIC_PATH" \
    --root "$STAGING" \
    --initdb \
    --update-cache \
    --allow-untrusted \
    --no-progress \
    --usermode \
    add "${ALPINE_PACKAGES[@]}" 2>&1

# Verify key binaries exist
log "Verifying installed binaries..."
local_fail=0
for bin in bash mkfs.ext4 mkfs.xfs quotacheck quotaon quotaoff repquota \
           mount umount losetup; do
    if [[ ! -f "$STAGING/usr/sbin/$bin" && ! -f "$STAGING/usr/bin/$bin" \
       && ! -f "$STAGING/sbin/$bin" && ! -f "$STAGING/bin/$bin" ]]; then
        err "Missing binary: $bin"
        local_fail=1
    fi
done
[[ $local_fail -eq 1 ]] && exit 1
log "All required binaries present"

# Step 6: Check for runuser or alternatives
if [[ -f "$STAGING/usr/bin/runuser" || -f "$STAGING/usr/sbin/runuser" \
   || -f "$STAGING/sbin/runuser" || -f "$STAGING/bin/runuser" ]]; then
    log "runuser available — configuring minimal PAM"
    # Minimal PAM config (same as existing RHEL rootfs)
    mkdir -p "$STAGING/etc/pam.d"
    for svc in runuser runuser-l su su-l other; do
        cat > "$STAGING/etc/pam.d/$svc" <<'PAM'
auth    sufficient  pam_rootok.so
auth    sufficient  pam_permit.so
account sufficient  pam_permit.so
session sufficient  pam_permit.so
PAM
    done
elif [[ -f "$STAGING/usr/bin/setpriv" || -f "$STAGING/bin/setpriv" ]]; then
    log "runuser not available, setpriv present (will need test script adjustment)"
else
    log "WARNING: neither runuser nor setpriv found"
fi

# Step 7: Install static quotatool
cp "$static_qt" "$STAGING/usr/bin/quotatool"
chmod +x "$STAGING/usr/bin/quotatool"
log "Installed static quotatool"

# Step 8: Install test scripts
mkdir -p "$STAGING/test"
cp -a "$TEST_DIR/guest-run-all.sh" "$STAGING/test/"
cp -a "$TEST_DIR/lib" "$STAGING/test/"
cp -a "$TEST_DIR/tests" "$STAGING/test/"
# Symlinks for test scripts that reference quotatool by relative path
ln -sf /usr/bin/quotatool "$STAGING/quotatool"
mkdir -p "$STAGING/src"
ln -sf /usr/bin/quotatool "$STAGING/src/quotatool"

# Step 9: Minimal /etc for tests
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

# /etc/mtab symlink
ln -sf /proc/mounts "$STAGING/etc/mtab"

# login.defs (runuser reads it)
touch "$STAGING/etc/login.defs"

# Step 10: Create directory structure expected by VM init
mkdir -p "$STAGING"/{dev,dev/pts,proc,sys,tmp,run,var/tmp,root}
chmod 1777 "$STAGING/tmp" "$STAGING/var/tmp" 2>/dev/null || true

# Step 11: Create the ext4 disk image
log "Creating ext4 disk image..."
mke2fs -q -t ext4 -O ^metadata_csum \
    -d "$STAGING" \
    "$ROOTFS_IMG" \
    "$ROOTFS_SIZE" 2>&1 | grep -v '^$' || true

img_size=$(du -h "$ROOTFS_IMG" | cut -f1)
staging_size=$(du -sh "$STAGING" | cut -f1)
log "alpine-rootfs.img built ($img_size, content $staging_size)"
log "Alpine $ALPINE_VERSION, $(wc -l < "$STAGING/etc/apk/world" 2>/dev/null || echo "?") packages"
