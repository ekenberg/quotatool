#!/bin/bash
# Build a minimal initramfs for raw QEMU boot path.
#
# Output: writes initramfs.cpio.gz to the same directory as this script.
#
# Requires: busybox (statically linked), cpio, gzip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/initramfs.cpio.gz"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Find static busybox — prefer our musl build, fall back to system
if [ -f "$SCRIPT_DIR/busybox-musl" ]; then
    BUSYBOX="$SCRIPT_DIR/busybox-musl"
elif command -v busybox >/dev/null 2>&1; then
    BUSYBOX=$(command -v busybox)
else
    echo "ERROR: no busybox found (run build-busybox.sh first, or install busybox)" >&2
    exit 1
fi
if ! file "$BUSYBOX" | grep -q 'statically'; then
    echo "WARNING: busybox at $BUSYBOX is not statically linked — may fail on old kernels" >&2
fi

# Create directory structure
mkdir -p "$WORK"/{bin,sbin,dev,proc,sys,mnt/host,mnt/results,tmp,run,etc}

# Install busybox + symlinks
cp "$BUSYBOX" "$WORK/bin/busybox"
chmod +x "$WORK/bin/busybox"

# Create symlinks for all busybox applets
for applet in sh mount umount mkdir cat echo chmod chroot poweroff \
              mknod ln ls cp mv rm sleep grep sed awk test \
              insmod losetup dd sync switch_root readlink; do
    ln -sf busybox "$WORK/bin/$applet"
    ln -sf ../bin/busybox "$WORK/sbin/$applet"
done

# Install our init script
cp "$SCRIPT_DIR/init" "$WORK/init"
chmod +x "$WORK/init"

# Build the cpio archive
(cd "$WORK" && find . | cpio -o -H newc --quiet | gzip -9) > "$OUTPUT"

echo "Built initramfs: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
