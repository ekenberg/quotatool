#!/bin/bash
# setup.sh — Download and provision FreeBSD cloud-init image for testing
#
# Idempotent: skips steps already completed.
# Run from repo root or via test/bsd/run-tests --setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BSD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGES_DIR="$BSD_DIR/images"
CLOUDINIT_DIR="$SCRIPT_DIR/cloud-init"

# FreeBSD 14.4 UFS cloud-init image
FREEBSD_VERSION="14.4"
FREEBSD_IMAGE="FreeBSD-${FREEBSD_VERSION}-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2"
FREEBSD_IMAGE_XZ="${FREEBSD_IMAGE}.xz"
FREEBSD_URL="https://download.freebsd.org/releases/VM-IMAGES/${FREEBSD_VERSION}-RELEASE/amd64/Latest/${FREEBSD_IMAGE_XZ}"

# Output paths
BASE_IMAGE="$IMAGES_DIR/$FREEBSD_IMAGE"
WORK_IMAGE="$IMAGES_DIR/freebsd-work.qcow2"
SEED_ISO="$IMAGES_DIR/freebsd-seed.iso"
SSH_KEY="$IMAGES_DIR/test-key"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { printf "\033[1m==> %s\033[0m\n" "$1"; }
ok()   { printf "\033[0;32m    OK: %s\033[0m\n" "$1"; }
skip() { printf "\033[0;33m    SKIP: %s\033[0m\n" "$1"; }

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

mkdir -p "$IMAGES_DIR"

# 1. Generate SSH key pair for test VMs
info "SSH key pair"
if [ -f "$SSH_KEY" ]; then
    skip "already exists: $SSH_KEY"
else
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "quotatool-bsd-test"
    ok "generated: $SSH_KEY"
fi

# 2. Inject SSH key into cloud-init user-data
info "Cloud-init user-data (SSH key injection)"
PUBKEY=$(cat "${SSH_KEY}.pub")
USER_DATA="$IMAGES_DIR/user-data"
# Replace ALL ssh_authorized_keys: [] placeholders with the real key
sed "s|ssh_authorized_keys: \[\]|ssh_authorized_keys:\n      - ${PUBKEY}|g" \
    "$CLOUDINIT_DIR/user-data" > "$USER_DATA"
ok "wrote $USER_DATA with SSH public key"

# 3. Download FreeBSD image
info "FreeBSD ${FREEBSD_VERSION} image"
if [ -f "$BASE_IMAGE" ]; then
    skip "already exists: $BASE_IMAGE"
else
    echo "    Downloading ${FREEBSD_IMAGE_XZ} (~660 MB)..."
    curl -L -f -# -o "$IMAGES_DIR/$FREEBSD_IMAGE_XZ" "$FREEBSD_URL"
    echo "    Decompressing..."
    xz -d "$IMAGES_DIR/$FREEBSD_IMAGE_XZ"
    ok "downloaded and decompressed: $BASE_IMAGE"
fi

# 4. Create seed ISO (cloud-init NoCloud datasource)
info "Cloud-init seed ISO"
# Always regenerate (SSH key may have changed)
genisoimage -output "$SEED_ISO" -volid cidata -joliet -rock \
    "$USER_DATA" "$CLOUDINIT_DIR/meta-data" 2>/dev/null
ok "created: $SEED_ISO"

# 5. Create CoW overlay (preserves base image)
info "CoW overlay image"
# Always regenerate (gives a fresh VM state)
qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$WORK_IMAGE" >/dev/null
ok "created: $WORK_IMAGE (backed by base image)"

# 6. First boot: run cloud-init provisioning and create snapshot
PROVISIONED="$IMAGES_DIR/freebsd-provisioned.qcow2"
info "Provisioned snapshot"
if [ -f "$PROVISIONED" ]; then
    skip "already exists: $PROVISIONED"
else
    echo "    Booting VM for cloud-init provisioning (~75s)..."

    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -o BatchMode=yes"

    qemu-system-x86_64 -enable-kvm -m 2G -smp 2 \
        -drive file="$WORK_IMAGE",if=virtio \
        -drive file="$SEED_ISO",if=virtio,media=cdrom \
        -device e1000,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -display none \
        -serial null \
        -daemonize \
        -pidfile "$IMAGES_DIR/qemu.pid"

    PID=$(cat "$IMAGES_DIR/qemu.pid")

    # Wait for root SSH access
    TIMEOUT=300
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if ! kill -0 "$PID" 2>/dev/null; then
            echo ""
            echo "ERROR: QEMU exited unexpectedly during provisioning"
            exit 1
        fi
        if ssh $SSH_OPTS -i "$SSH_KEY" -p 2222 root@localhost "echo OK" 2>/dev/null; then
            echo ""
            echo "    SSH ready after ${ELAPSED}s"
            break
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        printf "\r    Waiting for SSH... %ds" "$ELAPSED"
    done

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo ""
        echo "ERROR: SSH timeout during provisioning. Kill PID $PID manually."
        exit 1
    fi

    # Verify environment
    echo "    Verifying environment..."
    ssh $SSH_OPTS -i "$SSH_KEY" -p 2222 root@localhost \
        "sysctl kern.features.ufs_quota && id testuser && which gcc gmake" >/dev/null

    # Shut down cleanly
    echo "    Shutting down..."
    ssh $SSH_OPTS -i "$SSH_KEY" -p 2222 root@localhost "shutdown -p now" 2>/dev/null || true
    sleep 5
    kill "$PID" 2>/dev/null || true
    rm -f "$IMAGES_DIR/qemu.pid"
    sleep 2

    # Flatten CoW overlay into standalone provisioned image
    echo "    Creating provisioned snapshot (compressing, ~30s)..."
    qemu-img convert -f qcow2 -O qcow2 -c "$WORK_IMAGE" "$PROVISIONED"
    ok "created: $PROVISIONED ($(du -h "$PROVISIONED" | cut -f1))"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
info "FreeBSD setup complete"
echo "    Provisioned image: $PROVISIONED"
echo "    SSH key:           $SSH_KEY"
echo ""
echo "    Test runs create CoW overlays from the provisioned image."
echo "    Boot time: ~18s (no cloud-init, packages pre-installed)."
