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

# Find static busybox
BUSYBOX=$(which busybox 2>/dev/null || true)
if [ -z "$BUSYBOX" ]; then
    echo "ERROR: busybox not found in PATH" >&2
    exit 1
fi
if ! file "$BUSYBOX" | grep -q 'statically'; then
    echo "WARNING: busybox is not statically linked — may fail in minimal initramfs" >&2
fi

# Create directory structure
mkdir -p "$WORK"/{bin,sbin,dev,proc,sys,mnt/host,mnt/results,tmp,run,etc}

# Install busybox + symlinks
cp "$BUSYBOX" "$WORK/bin/busybox"
chmod +x "$WORK/bin/busybox"

# Create symlinks for all busybox applets
for applet in sh mount umount mkdir cat echo chmod chroot poweroff \
              mknod ln ls cp mv rm sleep grep sed awk test \
              losetup dd sync switch_root; do
    ln -sf busybox "$WORK/bin/$applet"
    ln -sf ../bin/busybox "$WORK/sbin/$applet"
done

# Install our init script
cp "$SCRIPT_DIR/init" "$WORK/init"
chmod +x "$WORK/init"

# Build the cpio archive
(cd "$WORK" && find . | cpio -o -H newc --quiet | gzip -9) > "$OUTPUT"

echo "Built initramfs: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
