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

# BASH_SOURCE works when sourced; $0 works when executed directly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "  ext4:     $EXT4_MNT  (writable: $EXT4_MNT/data)"
fi
if [[ "$WANT_FS" == "xfs" || "$WANT_FS" == "both" ]]; then
    echo "  XFS:      $XFS_MNT  (writable: $XFS_MNT/data)"
fi

cat <<'EOF'

  Examples:
    quotatool -u nobody -b -q 50M -l 100M /tmp/test-ext4
    runuser -u nobody -- dd if=/dev/zero of=/tmp/test-ext4/data/fill bs=1K count=200
    quotatool -d -u nobody /tmp/test-ext4
    repquota /tmp/test-ext4

  Type 'exit' to shut down the VM.

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
# If sourced (from shell wrapper or PROMPT_COMMAND), just set
# PS1 and return — caller provides the interactive shell.
# If executed directly (vng -e, or QEMU), drop to bash.
export PS1="quotatool-test# "
(return 0 2>/dev/null) && return 0

echo "  Note: no PTY — two warnings above are harmless."
echo "  No job control, no Ctrl-Z. Ctrl-C kills the VM."
echo ""

bash --norc --noprofile -i

# Shell exited — teardown happens via fs-setup EXIT trap
echo ""
echo "Tearing down filesystems and shutting down VM..."
