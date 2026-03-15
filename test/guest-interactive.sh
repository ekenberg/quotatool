#!/bin/bash
# guest-interactive.sh — interactive shell with quota filesystems ready
#
# Runs INSIDE the VM. Sets up ext4 and XFS quota filesystems, prints
# a help banner, then drops to an interactive bash shell. On exit,
# tears down filesystems and the VM powers off.
#
# Usage: guest-interactive.sh [fstype]
#   fstype: "ext4", "xfs", or "both" (default: both)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/lib/fs-setup.sh"
source "$SCRIPT_DIR/lib/test-ids.sh"
set +e  # fs-setup.sh enables -e via source; we don't want that here

# Ensure required modules
modprobe loop 2>/dev/null || true
modprobe quota_v2 2>/dev/null || true
modprobe quota_tree 2>/dev/null || true

WANT_FS="${1:-both}"
EXT4_MNT="/tmp/test-ext4"
XFS_MNT="/tmp/test-xfs"

# Set up filesystems
if [[ "$WANT_FS" == "ext4" || "$WANT_FS" == "both" ]]; then
    fs_create_ext4 "$EXT4_MNT" 200M
fi
if [[ "$WANT_FS" == "xfs" || "$WANT_FS" == "both" ]]; then
    fs_create_xfs "$XFS_MNT" 512M
fi

# Find quotatool
QT=""
for p in "$SCRIPT_DIR/../quotatool" /usr/bin/quotatool; do
    [[ -x "$p" ]] && QT="$p" && break
done

# Banner
cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║  quotatool interactive test shell                            ║
╚══════════════════════════════════════════════════════════════╝

  Kernel:    $(uname -r)
  quotatool: ${QT:-NOT FOUND}
  Test user: $TEST_USER_NAME (uid $TEST_USER_UID)
  Test group: $TEST_GROUP_NAME (gid $TEST_GROUP_GID)

EOF

if [[ "$WANT_FS" == "ext4" || "$WANT_FS" == "both" ]]; then
    echo "  ext4: $EXT4_MNT"
fi
if [[ "$WANT_FS" == "xfs" || "$WANT_FS" == "both" ]]; then
    echo "  XFS:  $XFS_MNT"
fi

if [[ -d "$EXT4_MNT/data" ]]; then
    echo "  ext4 writable dir: $EXT4_MNT/data (chmod 777, for runuser)"
fi
if [[ -d "$XFS_MNT/data" ]]; then
    echo "  XFS writable dir:  $XFS_MNT/data (chmod 777, for runuser)"
fi

cat <<'EOF'

  Examples:
    quotatool -u nobody -b -q 50M -l 100M /tmp/test-ext4
    quotatool -d -u nobody /tmp/test-ext4
    repquota /tmp/test-ext4
    runuser -u nobody -- dd if=/dev/zero of=/tmp/test-ext4/data/fill bs=1K count=200

  Type 'exit' to shut down the VM.
  Note: no PTY — no job control, no Ctrl-Z. Ctrl-C kills the VM.

EOF

# Make test dirs writable for runuser -u nobody
if [[ -d "$EXT4_MNT" ]]; then
    mkdir -p "$EXT4_MNT/data"
    chmod 777 "$EXT4_MNT/data"
fi
if [[ -d "$XFS_MNT" ]]; then
    mkdir -p "$XFS_MNT/data"
    chmod 777 "$XFS_MNT/data"
fi

# Drop to interactive shell.
# Note: when using vng -e, there's no proper PTY — job control and
# stdin redirection (cat >, here-docs) are unavailable. Normal
# commands (quotatool, repquota, dd, runuser) all work fine.
# Type 'exit' or 'poweroff' to shut down the VM.
export PS1="quotatool-test# "
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:$SCRIPT_DIR/.."
# Two harmless warnings will appear (no job control, cannot set terminal
# process group) — this is normal without a PTY. Everything works.
exec bash --norc --noprofile -i

# If bash exits, tear down (fs-setup EXIT trap handles cleanup)
echo ""
echo "Shell exited. Shutting down VM..."
