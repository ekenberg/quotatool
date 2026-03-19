#!/bin/bash
# fs-setup.sh — Create and manage quota-enabled UFS filesystems inside BSD VMs
#
# Creates loopback-mounted UFS filesystems with user and group quotas.
# Supports FreeBSD (mdconfig) and OpenBSD (vnconfig).
#
# Usage (after sourcing vm.sh and booting a VM):
#   source test/bsd/lib/fs-setup.sh
#   fs_create_ufs /mnt/quota-test 256M    # create + mount + enable quotas
#   fs_teardown /mnt/quota-test            # unmount + detach + cleanup
#   fs_teardown_all                        # cleanup everything

# ---------------------------------------------------------------------------
# State tracking
# ---------------------------------------------------------------------------

# Associative array: mountpoint → "device|image_file|os_type"
declare -A _FS_REGISTRY

# ---------------------------------------------------------------------------
# fs_detect_os
#   Detect whether the VM is running FreeBSD or OpenBSD.
#   Sets _FS_OS to "freebsd" or "openbsd".
# ---------------------------------------------------------------------------
_FS_OS=""

fs_detect_os() {
    if [ -n "$_FS_OS" ]; then
        return 0
    fi
    local uname
    uname=$(vm_run "uname -s")
    case "$uname" in
        FreeBSD) _FS_OS="freebsd" ;;
        OpenBSD) _FS_OS="openbsd" ;;
        *)
            echo "fs-setup: unsupported OS: $uname" >&2
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# fs_create_ufs <mountpoint> <size>
#   Create a loopback UFS filesystem with quotas enabled.
#   <size>: size string (e.g. 256M, 512M)
# ---------------------------------------------------------------------------
fs_create_ufs() {
    local mntpoint="${1:?Usage: fs_create_ufs <mountpoint> <size>}"
    local size="${2:-256M}"

    fs_detect_os

    local image_file="/tmp/quota-test-$$.img"
    local device=""

    # All commands run inside the VM
    case "$_FS_OS" in
        freebsd)
            # FreeBSD quota tools require an fstab entry.
            # We add a temporary one, then remove it on teardown.
            device=$(vm_run "
                set -e
                # Create sparse image
                truncate -s $size $image_file

                # Attach as memory disk
                device=\$(mdconfig -a -t vnode -f $image_file)

                # Create UFS filesystem
                newfs -U /dev/\$device >/dev/null

                # Add fstab entry (quota tools require it)
                echo \"/dev/\$device $mntpoint ufs rw,userquota,groupquota 0 0\" >> /etc/fstab

                # Mount via fstab (picks up quota options)
                mkdir -p $mntpoint
                mount $mntpoint

                # Initialize and enable quotas
                quotacheck -u -g $mntpoint
                quotaon $mntpoint

                # Output just the device name for capture
                echo \$device
            ")
            # Trim whitespace from captured device name
            device=$(echo "$device" | tr -d '[:space:]')
            ;;
        openbsd)
            device=$(vm_run "
                set -e
                # Create image file
                dd if=/dev/zero of=$image_file bs=1M count=${size%M} 2>/dev/null

                # Attach as vnode disk
                device=\$(vnconfig $image_file)

                # Create FFS filesystem on whole-disk partition (c)
                newfs /dev/r\${device}c >/dev/null

                # Add fstab entry (OpenBSD quota tools need it)
                echo \"/dev/\${device}c $mntpoint ffs rw,userquota,groupquota 0 0\" >> /etc/fstab

                # Mount via fstab
                mkdir -p $mntpoint
                mount $mntpoint

                # Create quota files and enable
                touch ${mntpoint}/quota.user ${mntpoint}/quota.group
                quotacheck -u -g $mntpoint
                quotaon $mntpoint

                echo \$device
            ")
            device=$(echo "$device" | tr -d '[:space:]')
            ;;
    esac

    # Track for cleanup
    _FS_REGISTRY["$mntpoint"]="${device}|${image_file}|${_FS_OS}"
    echo "[fs] Created UFS at $mntpoint (${size}, device=$device)"
}

# ---------------------------------------------------------------------------
# fs_teardown <mountpoint>
#   Unmount, detach device, remove image file.
# ---------------------------------------------------------------------------
fs_teardown() {
    local mntpoint="${1:?Usage: fs_teardown <mountpoint>}"

    local entry="${_FS_REGISTRY[$mntpoint]:-}"
    if [ -z "$entry" ]; then
        echo "[fs] Warning: $mntpoint not in registry" >&2
        return 0
    fi

    local device image_file os_type
    IFS='|' read -r device image_file os_type <<< "$entry"

    case "$os_type" in
        freebsd)
            vm_run "
                quotaoff $mntpoint 2>/dev/null || true
                umount -f $mntpoint 2>/dev/null || true
                mdconfig -d -u ${device#md} 2>/dev/null || true
                rm -f $image_file
                rmdir $mntpoint 2>/dev/null || true
                # Remove temporary fstab entry (use | as sed delimiter to avoid path escaping)
                sed -i '' '\\|${mntpoint}|d' /etc/fstab 2>/dev/null || true
            " 2>/dev/null || true
            ;;
        openbsd)
            vm_run "
                quotaoff $mntpoint 2>/dev/null || true
                umount -f $mntpoint 2>/dev/null || true
                vnconfig -u $device 2>/dev/null || true
                rm -f $image_file
                rmdir $mntpoint 2>/dev/null || true
                # Remove temporary fstab entry (use | as sed delimiter to avoid path escaping)
                sed -i '\\|${mntpoint}|d' /etc/fstab 2>/dev/null || true
            " 2>/dev/null || true
            ;;
    esac

    unset '_FS_REGISTRY[$mntpoint]'
    echo "[fs] Torn down $mntpoint"
}

# ---------------------------------------------------------------------------
# fs_teardown_all
#   Tear down all tracked filesystems.
# ---------------------------------------------------------------------------
fs_teardown_all() {
    for mntpoint in "${!_FS_REGISTRY[@]}"; do
        fs_teardown "$mntpoint"
    done
}
