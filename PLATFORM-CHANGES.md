# Platform Changes in v1.8.0

quotatool v1.8.0 drops support for macOS, AIX, Solaris, and NetBSD.
Linux, FreeBSD, and OpenBSD continue to be fully supported and tested.

Users on dropped platforms can continue using v1.7.x, which will
receive bug fixes.

## Platforms Dropped

### macOS

Apple's transition from HFS+ to APFS removed the foundation quotatool
depends on. APFS became the default filesystem in macOS 10.13 High
Sierra (September 2017) and does not implement `quotactl(2)` — the
POSIX interface for per-user and per-group filesystem quotas.

APFS has a concept of "quota size" on volumes, but it is fundamentally
different: it limits total volume size (set at creation time), not
per-user usage, and is managed through Disk Utility or `diskutil`, not
`quotactl`.

Apple's own `quotactl(2)` man page documents support only for "ffs"
and "hfs" filesystems — APFS is not mentioned. Users have reported
that `quotaon` fails on APFS since High Sierra, and the read-only
system volume introduced in macOS Catalina (10.15) further breaks
traditional quota workflows.

References:
- [Apple quotactl(2) man page](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/quotactl.2.html) — supports ffs and hfs only
- [Apple Disk Utility: File System Formats](https://support.apple.com/guide/disk-utility/file-system-formats-dsku19ed921c/mac) — APFS is "the default file system for Mac computers using macOS 10.13 or later"
- [Apple Discussion: quotaon fails on APFS](https://discussions.apple.com/thread/8191931) — reported since High Sierra
- [Apple Discussion: BSD quotas unworkable](https://discussions.apple.com/thread/253385872) — read-only root in Monterey

**Homebrew and MacPorts users**: quotatool v1.7.x continues to build
on macOS and will receive bug fixes. The
[Homebrew formula](https://github.com/Homebrew/homebrew-core/blob/master/Formula/q/quotatool.rb)
and [MacPorts port](https://ports.macports.org/port/quotatool/) can
continue to ship v1.7.x for users with HFS+ filesystems.

### AIX

AIX has a significant enterprise installed base, but IBM's quota
interface has diverged from the standard `quotactl` API. JFS2 (AIX's
primary filesystem) uses proprietary extensions — `Q_J2GETQUOTA`,
`Q_J2PUTLIMIT`, and a "limit class" system managed via `j2edlimit` —
that are incompatible with quotatool's approach.

No test environment is available, no AIX-related bug reports have been
filed, and the enterprise users who run AIX typically use IBM's own
tooling.

References:
- [AIX quotactl subroutine](https://www.ibm.com/docs/en/aix/7.2.0?topic=q-quotactl-subroutine) — documents JFS2-specific commands and non-standard headers
- [Setting JFS2 filesystem quotas](https://www.ibm.com/support/pages/setting-and-using-jfs2-filesystem-quotas) — uses AIX-specific `chfs` and `j2edlimit`

### Solaris / illumos

ZFS is the default root filesystem on Oracle Solaris 11 and all
illumos distributions. UFS is documented as "a supported legacy file
system" that is "not supported as a bootable root file system."

ZFS has its own quota system (`zfs set quota=`, `zfs set
userquota@user=`, `zfs set groupquota@group=`) that does not use
`quotactl`. quotatool's UFS-based approach is irrelevant on modern
Solaris/illumos installations.

References:
- [Transitioning to Oracle Solaris 11](https://docs.oracle.com/cd/E23824_01/html/E24456/filesystem-10.html) — "ZFS is the default root file system"
- [Solaris 11.4: Setting ZFS Quotas](https://docs.oracle.com/en/operating-systems/solaris/oracle-solaris/11.4/manage-zfs/setting-quotas-zfs-file-systems.html) — all quota management via `zfs set`
- [ZFS Quotas and Reservations](https://docs.oracle.com/cd/E23823_01/html/819-5461/gazvb.html) — per-user and per-group quotas via `zfs set`

### NetBSD

NetBSD 6.0 (October 2012) replaced `quotactl(2)` with a private
`__quotactl(2)` system call and a new `libquota(3)` library. The old
`quotactl(2)` interface that quotatool uses no longer exists. The
`__quotactl(2)` man page explicitly states it is "an internal
interface" and that "all application and utility code should use the
libquota(3) interface."

Porting quotatool to `libquota(3)` would require a full rewrite of
the NetBSD backend. Given NetBSD's small user base, this is currently
not justified.

References:
- [NetBSD __quotactl(2)](https://man.netbsd.org/__quotactl.2) — "an internal interface... appeared in NetBSD 6.0"
- [NetBSD libquota(3)](https://man.netbsd.org/libquota.3) — "first appeared in NetBSD 6.0"
- [NetBSD 6.0 Changes](https://www.netbsd.org/changes/changes-6.0.html) — "Removed quotactl(2) interface, replaced with new private __quotactl(2)"
- [NetBSD 6.0 Release](https://www.netbsd.org/releases/formal-6/NetBSD-6.0.html) — "rewritten disk quota subsystem"

## Platforms Kept

### Linux

Primary platform. Tested on 25+ vendor kernels spanning kernel 3.2
through 6.19, on ext4 and XFS. Supports old, vfsv0, vfsv1, and
generic quota formats.

### FreeBSD

Tested on FreeBSD 14.4. UFS quotas via `quotactl(2)` — stable API,
no recent changes.

### OpenBSD

Tested on OpenBSD 7.8. FFS quotas via `quotactl(2)` — traditional
BSD interface, conservative and stable.

## v1.7.x Maintenance

The v1.7.x line continues to support all platforms that v1.6.x did.
Bug fixes will be backported as needed.
