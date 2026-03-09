#!/bin/bash
# fs-setup.sh — loopback filesystem create/mount/teardown
# Functions to create ext4/XFS images with quotas enabled.
# Runs inside the VM.
#
# Public API:
#   fs_create_ext4 PATH SIZE   — create ext4 loopback with quotas at PATH
#   fs_create_xfs  PATH SIZE   — create XFS loopback with quotas at PATH
#   fs_teardown    PATH        — tear down a previously created filesystem
#   fs_teardown_all            — tear down all tracked filesystems
#
# PATH = mount point (e.g. /mnt/test-ext4)
# SIZE = image size understood by truncate (e.g. 100M, 1G)
#
# The library tracks all created filesystems and registers an EXIT trap
# to clean up on unexpected exit. Sourcing this file is safe — nothing
# runs until you call a function.

set -euo pipefail

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

# Associative array: mount_path -> "loop_dev|image_file|fstype"
declare -gA _FS_REGISTRY=()

# Whether we've already installed the EXIT trap
declare -g _FS_TRAP_INSTALLED=0

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_fs_log() {
    echo "fs-setup: $*" >&2
}

_fs_err() {
    echo "fs-setup: ERROR: $*" >&2
}

# ---------------------------------------------------------------------------
# EXIT trap — clean teardown on unexpected exit
# ---------------------------------------------------------------------------

_fs_exit_handler() {
    local rc=$?
    if [[ ${#_FS_REGISTRY[@]} -gt 0 ]]; then
        _fs_log "exit trap: cleaning up ${#_FS_REGISTRY[@]} filesystem(s)"
        fs_teardown_all
    fi
    return "$rc"
}

_fs_install_trap() {
    if [[ $_FS_TRAP_INSTALLED -eq 0 ]]; then
        trap _fs_exit_handler EXIT
        _FS_TRAP_INSTALLED=1
    fi
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Register a filesystem in the tracking table.
# Args: mount_path loop_dev image_file fstype
_fs_register() {
    local mnt="$1" loop="$2" img="$3" fstype="$4"
    _FS_REGISTRY["$mnt"]="${loop}|${img}|${fstype}"
    _fs_install_trap
}

# Look up registry entry. Sets _REG_LOOP, _REG_IMG, _REG_FSTYPE.
# Returns 1 if not found.
_fs_lookup() {
    local mnt="$1"
    local entry="${_FS_REGISTRY[$mnt]:-}"
    if [[ -z "$entry" ]]; then
        return 1
    fi
    IFS='|' read -r _REG_LOOP _REG_IMG _REG_FSTYPE <<< "$entry"
    return 0
}

# Unregister a mount point from tracking.
_fs_unregister() {
    unset '_FS_REGISTRY['"$1"']'
}

# Find the loop device backing an image file.
# Outputs the device path (e.g. /dev/loop0). Returns 1 if none found.
_fs_find_loop_for_image() {
    local img="$1"
    losetup -j "$img" 2>/dev/null | cut -d: -f1 | head -n1
}

# Check if a path is currently mounted.
_fs_is_mounted() {
    mountpoint -q "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# fs_create_ext4 — create a loopback ext4 filesystem with quotas
# ---------------------------------------------------------------------------
# Args:
#   $1  Mount point path (will be created if missing)
#   $2  Image size (truncate format: 100M, 1G, etc.)
#
# Flow:
#   1. Create sparse image file
#   2. Attach to loop device
#   3. mkfs.ext4 (quiet, with quota feature)
#   4. Mount with usrquota,grpquota
#   5. quotacheck -ugm to initialize aquota.user / aquota.group
#   6. quotaon to enable quota enforcement
#   7. Verify with repquota
#
# On failure at any step, cleans up everything done so far.

fs_create_ext4() {
    local mnt="$1"
    local size="$2"
    local img="${mnt}.img"
    local loop=""

    _fs_log "creating ext4 filesystem: mount=$mnt size=$size"

    # Partial-state tracking for cleanup on failure
    local _cleanup_img="" _cleanup_loop="" _cleanup_mnt=""

    _fs_ext4_cleanup_on_error() {
        _fs_err "ext4 creation failed at $mnt — cleaning up partial state"
        if [[ -n "$_cleanup_mnt" ]] && _fs_is_mounted "$_cleanup_mnt"; then
            umount "$_cleanup_mnt" 2>/dev/null || true
        fi
        if [[ -n "$_cleanup_loop" ]]; then
            losetup -d "$_cleanup_loop" 2>/dev/null || true
        fi
        if [[ -n "$_cleanup_img" ]] && [[ -f "$_cleanup_img" ]]; then
            rm -f "$_cleanup_img"
        fi
        if [[ -n "$_cleanup_mnt" ]] && [[ -d "$_cleanup_mnt" ]]; then
            rmdir "$_cleanup_mnt" 2>/dev/null || true
        fi
    }

    # 1. Create sparse image
    if ! truncate -s "$size" "$img"; then
        _fs_err "failed to create image file $img"
        return 1
    fi
    _cleanup_img="$img"

    # 2. Attach loop device
    loop=$(losetup --find --show "$img") || {
        _fs_ext4_cleanup_on_error
        return 1
    }
    _cleanup_loop="$loop"
    _fs_log "  loop device: $loop"

    # 3. mkfs.ext4 with quota feature enabled
    #    -O quota enables kernel-level quota support (ext4 >= 3.15).
    #    With this feature, quotas are active at mount time — no
    #    quotacheck or quotaon needed.
    #    Caveats:
    #    - Kernels < ~4.5 can mount -O quota but don't enforce limits.
    #    - Kernels < 3.15 can't mount -O quota at all.
    #    For kernels < 4.5, force the legacy quotacheck+quotaon path
    #    which enforces properly.
    local has_builtin_quota=0
    local mkfs_ok=0
    local force_legacy=0
    local kver_major kver_minor
    kver_major=$(uname -r | cut -d. -f1)
    kver_minor=$(uname -r | cut -d. -f2)
    if [[ $kver_major -lt 4 || ($kver_major -eq 4 && $kver_minor -lt 5) ]]; then
        force_legacy=1
        _fs_log "  kernel $kver_major.$kver_minor < 4.5: forcing legacy quota path"
    fi

    if [[ "$force_legacy" -eq 0 ]] && mkfs.ext4 -q -O quota "$loop" >/dev/null 2>&1; then
        mkfs_ok=1
    fi

    # 4. Mount — try progressively simpler formats on mount failure.
    #    Modern mkfs.ext4 creates features (metadata_csum, 64bit) that
    #    old kernels can't mount. Fall back to stripping them.
    mkdir -p "$mnt"
    _cleanup_mnt="$mnt"
    if [[ "$mkfs_ok" -eq 1 ]]; then
        if mount -o usrquota,grpquota "$loop" "$mnt" 2>/dev/null; then
            has_builtin_quota=1
            _fs_log "  mounted at $mnt"
        else
            # -O quota mount failed — fall through to legacy path
            _fs_log "  mount with -O quota failed, falling back to legacy"
            mkfs_ok=0
        fi
    fi

    if [[ "$mkfs_ok" -eq 0 ]]; then
        # Try progressively simpler ext4 formats until one mounts
        local ext4_mounted=0
        local -a ext4_attempts=(
            "-q"
            "-q -O ^metadata_csum"
            "-q -O ^metadata_csum,^64bit"
        )
        for ext4_flags in "${ext4_attempts[@]}"; do
            # shellcheck disable=SC2086
            if mkfs.ext4 $ext4_flags "$loop" >/dev/null 2>&1; then
                if mount -o usrquota,grpquota "$loop" "$mnt" 2>/dev/null; then
                    ext4_mounted=1
                    _fs_log "  mounted at $mnt (mkfs.ext4 $ext4_flags)"
                    break
                fi
            fi
        done
        if [[ "$ext4_mounted" -eq 0 ]]; then
            _fs_err "ext4: all format attempts failed"
            _fs_ext4_cleanup_on_error
            return 1
        fi
    fi

    # 5+6. Enable quotas
    if [[ "$has_builtin_quota" -eq 1 ]]; then
        # Built-in quota: already active from mount. Nothing to do.
        _fs_log "  quotas enabled via -O quota (built-in)"
    else
        # Legacy path: quotacheck to create accounting files, then quotaon
        if ! quotacheck -ugm "$mnt" 2>/dev/null; then
            _fs_err "quotacheck failed on $mnt"
            _fs_ext4_cleanup_on_error
            return 1
        fi
        if ! quotaon "$mnt" 2>/dev/null; then
            _fs_err "quotaon failed on $mnt"
            _fs_ext4_cleanup_on_error
            return 1
        fi
        _fs_log "  quotas enabled via quotacheck+quotaon (legacy)"
    fi

    # 7. Verify — repquota should return 0
    if ! repquota "$mnt" >/dev/null 2>&1; then
        _fs_err "repquota verification failed on $mnt"
        _fs_ext4_cleanup_on_error
        return 1
    fi

    # Success — register for tracking
    _fs_register "$mnt" "$loop" "$img" "ext4"
    _fs_log "  ext4 filesystem ready at $mnt"
    return 0
}

# ---------------------------------------------------------------------------
# fs_create_xfs — create a loopback XFS filesystem with quotas
# ---------------------------------------------------------------------------
# Args:
#   $1  Mount point path
#   $2  Image size (truncate format)
#
# Flow:
#   1. Create sparse image file
#   2. Attach to loop device
#   3. mkfs.xfs
#   4. Mount with uquota,gquota — XFS enables quotas at mount time
#   5. No quotacheck needed (XFS manages quota accounting internally)
#   6. Verify with repquota
#
# Note: XFS has a minimum filesystem size (around 16M with default settings).
# Use at least 32M to be safe.

fs_create_xfs() {
    local mnt="$1"
    local size="$2"
    local img="${mnt}.img"
    local loop=""

    _fs_log "creating XFS filesystem: mount=$mnt size=$size"

    local _cleanup_img="" _cleanup_loop="" _cleanup_mnt=""

    _fs_xfs_cleanup_on_error() {
        _fs_err "XFS creation failed at $mnt — cleaning up partial state"
        if [[ -n "$_cleanup_mnt" ]] && _fs_is_mounted "$_cleanup_mnt"; then
            umount "$_cleanup_mnt" 2>/dev/null || true
        fi
        if [[ -n "$_cleanup_loop" ]]; then
            losetup -d "$_cleanup_loop" 2>/dev/null || true
        fi
        if [[ -n "$_cleanup_img" ]] && [[ -f "$_cleanup_img" ]]; then
            rm -f "$_cleanup_img"
        fi
        if [[ -n "$_cleanup_mnt" ]] && [[ -d "$_cleanup_mnt" ]]; then
            rmdir "$_cleanup_mnt" 2>/dev/null || true
        fi
    }

    # 1. Create sparse image
    if ! truncate -s "$size" "$img"; then
        _fs_err "failed to create image file $img"
        return 1
    fi
    _cleanup_img="$img"

    # 2. Attach loop device
    loop=$(losetup --find --show "$img") || {
        _fs_xfs_cleanup_on_error
        return 1
    }
    _cleanup_loop="$loop"
    _fs_log "  loop device: $loop"

    # 3+4. mkfs.xfs + mount
    #    Try progressively simpler XFS formats until one works:
    #    1. Default (modern: crc=1, reflink=1) — kernels >=5.1 or so
    #    2. reflink=0 — kernels >=3.15 without CONFIG_XFS_REFLINK
    #    3. crc=0 (XFS v4) — kernels <3.15
    #    This avoids hardcoding kernel version cutoffs that don't account
    #    for vendor kernel CONFIG differences.
    mkdir -p "$mnt"
    _cleanup_mnt="$mnt"
    local xfs_mounted=0
    local -a format_attempts=(
        "-f"
        "-f -m reflink=0"
        "-f -m crc=0,finobt=0,rmapbt=0,reflink=0"
        "-f -m crc=0,finobt=0,rmapbt=0,reflink=0 -n ftype=0"
    )
    for mkfs_flags in "${format_attempts[@]}"; do
        # shellcheck disable=SC2086
        if mkfs.xfs $mkfs_flags "$loop" >/dev/null 2>&1; then
            if mount -o uquota,gquota "$loop" "$mnt" 2>/dev/null; then
                xfs_mounted=1
                _fs_log "  mounted at $mnt (mkfs.xfs $mkfs_flags)"
                break
            fi
            _fs_log "  mount failed with $mkfs_flags, trying simpler format"
        fi
    done
    if [[ "$xfs_mounted" -eq 0 ]]; then
        _fs_err "XFS: all format attempts failed"
        _fs_xfs_cleanup_on_error
        return 1
    fi

    # 5. No quotacheck needed — XFS handles this internally

    # 6. Verify — repquota should return 0
    if ! repquota "$mnt" >/dev/null 2>&1; then
        _fs_err "repquota verification failed on $mnt"
        _fs_xfs_cleanup_on_error
        return 1
    fi

    # Success — register for tracking
    _fs_register "$mnt" "$loop" "$img" "xfs"
    _fs_log "  XFS filesystem ready at $mnt"
    return 0
}

# ---------------------------------------------------------------------------
# fs_teardown — tear down a single filesystem
# ---------------------------------------------------------------------------
# Args:
#   $1  Mount point path (as passed to fs_create_*)
#
# Flow:
#   1. quotaoff (ignore errors — XFS doesn't need it, and a failed
#      mount won't have quotas on)
#   2. umount
#   3. losetup -d to detach the loop device
#   4. rm image file
#   5. rmdir mount point
#
# Handles partial state gracefully: each step checks whether there's
# anything to do before acting. Never fails hard — logs errors and
# continues cleanup.

fs_teardown() {
    local mnt="$1"
    local loop="" img="" fstype=""
    local errors=0

    _fs_log "tearing down: $mnt"

    # Try to get info from registry first
    if _fs_lookup "$mnt"; then
        loop="$_REG_LOOP"
        img="$_REG_IMG"
        fstype="$_REG_FSTYPE"
    else
        # Not in registry — try to figure it out from system state.
        # This handles cases where the script was re-sourced or state was lost.
        img="${mnt}.img"
        if [[ -f "$img" ]]; then
            loop=$(_fs_find_loop_for_image "$img") || true
        fi
        fstype="unknown"
        _fs_log "  not in registry, inferring: loop=${loop:-none} img=$img"
    fi

    # 1. quotaoff — disable quota enforcement
    #    XFS doesn't use quotaoff (quotas are mount-level), but calling it
    #    is harmless. Ignore all errors.
    if _fs_is_mounted "$mnt"; then
        quotaoff "$mnt" 2>/dev/null || true
    fi

    # 2. umount
    if _fs_is_mounted "$mnt"; then
        if ! umount "$mnt" 2>/dev/null; then
            # Lazy unmount as fallback — better than leaking
            _fs_err "normal umount failed, trying lazy umount: $mnt"
            if ! umount -l "$mnt" 2>/dev/null; then
                _fs_err "lazy umount also failed: $mnt"
                errors=$((errors + 1))
            fi
        fi
        _fs_log "  unmounted $mnt"
    else
        _fs_log "  not mounted (skipping umount)"
    fi

    # 3. Detach loop device
    if [[ -n "$loop" ]] && [[ -b "$loop" ]]; then
        if ! losetup -d "$loop" 2>/dev/null; then
            _fs_err "failed to detach loop device: $loop"
            errors=$((errors + 1))
        else
            _fs_log "  detached $loop"
        fi
    else
        _fs_log "  no loop device to detach"
    fi

    # 4. Remove image file
    if [[ -n "$img" ]] && [[ -f "$img" ]]; then
        rm -f "$img"
        _fs_log "  removed $img"
    fi

    # 5. Remove mount point directory (only if empty)
    if [[ -d "$mnt" ]]; then
        rmdir "$mnt" 2>/dev/null || true
    fi

    # Unregister
    _fs_unregister "$mnt"

    if [[ $errors -gt 0 ]]; then
        _fs_err "teardown completed with $errors error(s): $mnt"
        return 1
    fi

    _fs_log "  teardown complete: $mnt"
    return 0
}

# ---------------------------------------------------------------------------
# fs_teardown_all — tear down every tracked filesystem
# ---------------------------------------------------------------------------
# Called by the EXIT trap and available for explicit use.
# Continues through errors — best effort cleanup.

fs_teardown_all() {
    local had_errors=0

    # Copy keys to array first — can't modify assoc array while iterating
    local mnts=("${!_FS_REGISTRY[@]}")

    for mnt in "${mnts[@]}"; do
        fs_teardown "$mnt" || had_errors=1
    done

    if [[ $had_errors -ne 0 ]]; then
        _fs_err "teardown_all completed with errors"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# fs_list — list currently tracked filesystems (for debugging)
# ---------------------------------------------------------------------------

fs_list() {
    if [[ ${#_FS_REGISTRY[@]} -eq 0 ]]; then
        echo "fs-setup: no tracked filesystems"
        return 0
    fi
    echo "fs-setup: tracked filesystems:"
    local mnt
    for mnt in "${!_FS_REGISTRY[@]}"; do
        local entry="${_FS_REGISTRY[$mnt]}"
        IFS='|' read -r loop img fstype <<< "$entry"
        echo "  $mnt  [$fstype]  loop=$loop  img=$img"
    done
}
