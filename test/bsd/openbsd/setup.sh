#!/bin/bash
# setup.sh — Automated OpenBSD installation and provisioning for testing
#
# Uses CD boot + HTTP-served install.conf + QEMU monitor sendkey.
# The installer runs on VGA (headless), we interact via monitor and SSH.
#
# Flow:
#   1. Start Python HTTP server on host port 8080 (serves install.conf)
#   2. Boot from CD ISO in QEMU (display=none, monitor on TCP)
#   3. Send 'a' (Autoinstall) via QEMU monitor sendkey
#   4. Installer asks for response file → send URL with port 8080
#   5. autoinstall reads install.conf, downloads sets from CDN
#   6. After install: eject CD, reboot → boots from disk
#   7. SSH in, install packages, configure
#   8. Shutdown, snapshot
#
# Idempotent: skips steps already completed.
# Requires: qemu, mtools (for floppy), python3, curl, xz
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BSD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGES_DIR="$BSD_DIR/images"

# OpenBSD 7.8
OPENBSD_VERSION="7.8"
OPENBSD_SHORT="78"
OPENBSD_ISO="cd${OPENBSD_SHORT}.iso"
OPENBSD_URL="https://cdn.openbsd.org/pub/OpenBSD/${OPENBSD_VERSION}/amd64/${OPENBSD_ISO}"

# Output paths
ISO_PATH="$IMAGES_DIR/$OPENBSD_ISO"
DISK_IMAGE="$IMAGES_DIR/openbsd-disk.qcow2"
PROVISIONED="$IMAGES_DIR/openbsd-provisioned.qcow2"
SSH_KEY="$IMAGES_DIR/test-key"

SSH_PORT=2223
MONITOR_PORT=4444
HTTP_PORT=8080
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { printf "\033[1m==> %s\033[0m\n" "$1"; }
ok()   { printf "\033[0;32m    OK: %s\033[0m\n" "$1"; }
skip() { printf "\033[0;33m    SKIP: %s\033[0m\n" "$1"; }
err()  { printf "\033[0;31m    ERROR: %s\033[0m\n" "$1" >&2; }

# Send commands to QEMU monitor via TCP
qemu_monitor() {
    python3 -c "
import socket, time, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', $MONITOR_PORT))
time.sleep(0.3)
s.recv(4096)
for cmd in sys.argv[1:]:
    s.sendall((cmd + '\n').encode())
    time.sleep(0.3)
    try: s.recv(4096)
    except: pass
s.close()
" "$@"
}

# Send text as keystrokes via QEMU monitor
qemu_type() {
    local text="$1"
    python3 -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('127.0.0.1', $MONITOR_PORT))
time.sleep(0.3)
s.recv(4096)
text = '''$text'''
for ch in text:
    if ch == ':': key = 'shift-semicolon'
    elif ch == '/': key = 'slash'
    elif ch == '.': key = 'dot'
    elif ch == '-': key = 'minus'
    elif ch == '_': key = 'shift-minus'
    else: key = ch
    s.sendall(('sendkey ' + key + '\n').encode())
    time.sleep(0.05)
    try: s.recv(4096)
    except: pass
time.sleep(0.2)
s.sendall(b'sendkey ret\n')
time.sleep(0.3)
try: s.recv(4096)
except: pass
s.close()
"
}

cleanup() {
    # Kill HTTP server if running
    [ -n "${HTTP_PID:-}" ] && kill "$HTTP_PID" 2>/dev/null || true
    # Kill QEMU if running
    local pid_file="$IMAGES_DIR/qemu-openbsd.pid"
    [ -f "$pid_file" ] && kill "$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$pid_file"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

mkdir -p "$IMAGES_DIR"

# 1. SSH key (shared with FreeBSD)
info "SSH key pair"
if [ -f "$SSH_KEY" ]; then
    skip "already exists: $SSH_KEY"
else
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "quotatool-bsd-test"
    ok "generated: $SSH_KEY"
fi

# 2. Download OpenBSD install ISO
info "OpenBSD ${OPENBSD_VERSION} install ISO"
if [ -f "$ISO_PATH" ]; then
    skip "already exists: $ISO_PATH"
else
    echo "    Downloading ${OPENBSD_ISO} (~11 MB)..."
    curl -L -f -# -o "$ISO_PATH" "$OPENBSD_URL"
    ok "downloaded: $ISO_PATH"
fi

# 3. Check if already provisioned
info "Provisioned image"
if [ -f "$PROVISIONED" ]; then
    skip "already exists: $PROVISIONED"
    echo ""
    info "OpenBSD setup complete (using existing provisioned image)"
    exit 0
fi

# 4. Prepare install.conf and HTTP server
info "Preparing install.conf"
SERVE_DIR=$(mktemp -d)
PUBKEY=$(cat "${SSH_KEY}.pub")
sed "s|SSH_PUBKEY_PLACEHOLDER|${PUBKEY}|" "$SCRIPT_DIR/install.conf" > "$SERVE_DIR/install.conf"

python3 -m http.server "$HTTP_PORT" --directory "$SERVE_DIR" &
HTTP_PID=$!
sleep 1
ok "HTTP server on port $HTTP_PORT (PID $HTTP_PID)"

# 5. Create disk image
info "Creating disk image"
qemu-img create -f qcow2 "$DISK_IMAGE" 6G >/dev/null
ok "created: $DISK_IMAGE (6G)"

# 6. Boot from CD, run autoinstall via QEMU monitor
info "Running OpenBSD installation"
echo "    This downloads ~300MB of sets from cdn.openbsd.org"
echo "    and takes approximately 5-10 minutes..."

qemu-system-x86_64 -enable-kvm -m 2G -smp 2 \
    -drive "file=$DISK_IMAGE,media=disk,if=virtio" \
    -cdrom "$ISO_PATH" \
    -boot d \
    -device e1000,netdev=net0 \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -display none \
    -monitor "tcp:127.0.0.1:${MONITOR_PORT},server,nowait" \
    -serial null \
    -daemonize \
    -pidfile "$IMAGES_DIR/qemu-openbsd.pid"

QEMU_PID=$(cat "$IMAGES_DIR/qemu-openbsd.pid")
echo "    QEMU PID: $QEMU_PID"

# Wait for kernel boot (~45s)
echo "    Waiting 45s for kernel boot..."
sleep 45

if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    err "QEMU exited during boot"
    exit 1
fi

# Send 'a' for Autoinstall
echo "    Sending 'A' (Autoinstall)..."
qemu_monitor "sendkey a" "sendkey ret"

# Wait for response file prompt (~5s)
sleep 5

# Send URL to our HTTP server with install.conf
echo "    Sending install.conf URL..."
qemu_type "http://10.0.2.2:${HTTP_PORT}/install.conf"
ok "autoinstall initiated"

# Wait for install to complete — monitor by watching for the system to reboot.
# After install, OpenBSD reboots. Since -boot d, it boots from CD again.
# We detect this by waiting, then ejecting CD and resetting.
echo "    Waiting for install to complete (up to 10 min)..."
TIMEOUT=600
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        err "QEMU exited during install"
        exit 1
    fi
    sleep 30
    ELAPSED=$((ELAPSED + 30))
    printf "."
done
# If we hit timeout, try ejecting CD anyway — install likely completed
echo ""

# Eject CD and reboot from disk
echo "    Ejecting CD and rebooting from disk..."
qemu_monitor "eject -f ide1-cd0" "system_reset"

# Wait for SSH
echo "    Waiting for SSH..."
TIMEOUT=120
ELAPSED=0
SSH_OK=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if ssh $SSH_OPTS -i "$SSH_KEY" -p "$SSH_PORT" root@localhost "true" 2>/dev/null; then
        echo ""
        echo "    SSH ready after ${ELAPSED}s"
        SSH_OK=1
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ "$SSH_OK" -eq 0 ]; then
    err "SSH timeout after CD eject. Installation may have failed."
    exit 1
fi

ok "OpenBSD base installation complete"

# Stop HTTP server — no longer needed
kill "$HTTP_PID" 2>/dev/null || true
HTTP_PID=""
rm -rf "$SERVE_DIR"

# 7. Post-install configuration
info "Post-install configuration"
echo "    Installing packages..."
ssh $SSH_OPTS -i "$SSH_KEY" -p "$SSH_PORT" root@localhost "
    echo 'https://cdn.openbsd.org/pub/OpenBSD' > /etc/installurl
    pkg_add -I gcc-11.2.0p19 gmake autoconf-2.72p0 automake-1.17 git bash

    # Symlinks for GCC
    [ -x /usr/local/bin/egcc ] && ln -sf /usr/local/bin/egcc /usr/local/bin/gcc
    [ -x /usr/local/bin/eg++ ] && ln -sf /usr/local/bin/eg++ /usr/local/bin/g++

    # autoconf/automake version env vars
    echo 'export AUTOCONF_VERSION=2.72' >> /root/.profile
    echo 'export AUTOMAKE_VERSION=1.17' >> /root/.profile

    # Test user
    groupadd -g 60000 testgroup 2>/dev/null || true
    useradd -u 60000 -g 60000 -d /home/testuser -m -s /bin/sh testuser 2>/dev/null || true

    echo 'Configuration complete'
"

# Verify
echo "    Verifying..."
ssh $SSH_OPTS -i "$SSH_KEY" -p "$SSH_PORT" root@localhost "
    . /root/.profile 2>/dev/null
    uname -a
    id testuser
    gcc --version 2>/dev/null | head -1
    which gmake autoconf bash
"

# 8. Shutdown and snapshot
info "Shutting down"
ssh $SSH_OPTS -i "$SSH_KEY" -p "$SSH_PORT" root@localhost "shutdown -p now" 2>/dev/null || true
WAITED=0
while kill -0 "$QEMU_PID" 2>/dev/null && [ $WAITED -lt 30 ]; do
    sleep 2
    WAITED=$((WAITED + 2))
done
kill "$QEMU_PID" 2>/dev/null || true
sleep 2

info "Creating provisioned snapshot"
echo "    Compressing..."
qemu-img convert -f qcow2 -O qcow2 -c "$DISK_IMAGE" "$PROVISIONED"
ok "created: $PROVISIONED ($(du -h "$PROVISIONED" | cut -f1))"

# Cleanup
rm -f "$DISK_IMAGE"

echo ""
info "OpenBSD setup complete"
echo "    Provisioned image: $PROVISIONED"
echo "    SSH key:           $SSH_KEY"
echo "    SSH port:          $SSH_PORT"
