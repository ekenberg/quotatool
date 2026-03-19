quotatool
=========

> **[Roadmap](ROADMAP.md)** — upcoming releases and platform changes.

> **[Platform Changes](PLATFORM-CHANGES.md)** — v1.8.0 drops support for macOS, AIX, Solaris, and NetBSD.

![Quotatool](http://quotatool.ekenberg.se/diskusage.gif) Commandline utility for filesystem quotas on Linux, FreeBSD and OpenBSD

*Set 50Gb soft and hard diskusage limits for user johan on filesystem /home*

    quotatool -u johan -b -q 50G -l 50G /home

*See more examples below*

## Installation

### Linux

*quotatool is already in your package manager:*

* Ubuntu, Mint, Debian:
    `sudo apt-get install quotatool`
* Fedora, Red Hat, CentOS, AlmaLinux, Rocky Linux:
    `dnf install quotatool`
    `yum install quotatool`
    (on RHEL-derivatives, quotatool is in the [EPEL](https://docs.fedoraproject.org/en-US/epel/) repository)
* openSUSE:
    `zypper install quotatool`
* Gentoo Linux:
    `emerge quotatool`

### Install from source code

    ./configure
    make
    sudo make install
    (use gmake on *BSD)

## Usage

    quotatool { -u uid | -g gid } [ options ... ] filesystem
    quotatool { -u | -g } { -i | -b } -t time filesystem
    quotatool { -u uid | -g gid } -r filesystem
    quotatool { -u uid | -g gid } -d filesystem

Both -u (user) and -g (group) quotas are supported on all platforms.


### Arguments and Options

```
   -u uid  username or uid.
   -g gid  groupname or gid.
      	   See examples below how to handle non-existent uid/gid

   -b      set block limits
   -i      set inode limits

   -q n    set soft limit to n blocks/inodes
   -l n    set hard limit to n blocks/inodes

   quotatool accepts the units Kb, Mb, Gb, Tb, bytes and blocks
   to modify limit arguments. Units are base 2 for blocks (1k = 1024)
   and base 10 for inodes (1k = 1000).
   Use +/- to raise/lower quota by the specified amount.
   n can be integer or floating point
   See examples below.

   -R      Raise only - avoid accidentally lowering quotas for a user/group

   -t      time set global grace period to time.
           The time parameter consists of an optional
           '+' or '-' modifier, a  number, and one of:
           'sec', 'min', 'hour', 'day', 'week', and
           'month'.  If a +/- modifier is present, the
           current quota will be increased/reduced by
           the amount specified

   -r      restart grace period for uid or gid

   -h      print a usage message

   -v      verbose mode -- print status messages during execution
           use this twice for even more information

   -n      do everything except set the quota.  useful with -v
           to see what is supposed to happen

   -V      show version

   filesystem is either device name (eg /dev/sda1) or mountpoint (eg /home)
```

## Examples

Set soft block limit to 800Mb, hard block limit to 1.2 Gb for user mpg4 on /home:

    quotatool -u mpg4 -b -q 800M -l 1.2G /home

Raise soft block limit by 100M for non-existent gid 12345 on /dev/loop3:

    quotatool -g :12345 -b -q +100M /dev/loop3

Set soft inode limit to 1.8k (1800), hard inode limit to 2000 for user johan on /var:

    quotatool -u johan -i -q 1.8K -l 2000 /var

Set the global block grace period to one week on /home:

    quotatool -u -b -t "1 week" /home

Restart inode grace period for user johan on root filesystem:

    quotatool -u johan -i -r /


## Notes

* Grace periods are set on a "global per quotatype and filesystem" basis only.
Each quotatype (usrquota / grpquota) on each filesystem has two grace periods
- one for block limits and one for inode limits.
It is not possible to set different grace periods for users on the same filesystem.

BSD-note: On BSD (FreeBSD, OpenBSD), the grace period is cached by the kernel
at `quotaon` time. After setting the grace period with `-t`, a `quotaoff`/`quotaon`
cycle is required for the new value to take effect. This is the same behavior as
`edquota -t` on BSD — it is a BSD kernel design choice, not a limitation of quotatool.

* Using non-existent uids/gids like ":12345" can be useful when configuring quotas on
a mounted filesystem which is a separate system in it self, like when preparing an
install image or repairing a filesystem from another installation.

* Limit arguments can be specified in several ways, these are all equivalent:
  1M
  1m
  1Mb
  1 "Mb"

* Use +/- to raise/lower quotas relative to current limits

* Use -v (or -v -v) to see verbose/debug info when running commands

## Platforms and Filesystems

quotatool currently builds and works well on:

-- Linux --
Quota formats: old, vfsv0, vfsv1 and "generic"
Filesystems: ext2, ext3, ext4, ReiserFS and XFS

-- BSD --
FreeBSD, OpenBSD (UFS, FFS)

See [PLATFORM-CHANGES.md](PLATFORM-CHANGES.md) for details on
platforms dropped in v1.8.0 (macOS, AIX, Solaris, NetBSD).
Users on these platforms can use quotatool v1.7.x, which continues
to receive bug fixes.

Missing a feature or found a bug?
Add an issue on https://github.com/ekenberg/quotatool/issues

## Testing

quotatool includes a multi-kernel test suite that boots vendor kernels in
QEMU/virtme-ng VMs and tests quota operations on both ext4 and XFS.

The kernel matrix covers actively supported Linux distros (Ubuntu,
Debian, RHEL/Alma/CentOS, Fedora, openSUSE) plus recently EOL and
historical versions for regression coverage. Kernels are grouped
into three tiers:

- **Tier 1**: Actively supported distros — must test before release
- **Tier 2**: Recently EOL or significant niche — should test
- **Tier 3**: Historical/EOL — nice to have, catches regressions

Run `test/run-tests --list` to see the current matrix.

### Prerequisites

Linux host with KVM support (`/dev/kvm` must exist and be accessible).
If `/dev/kvm` exists but isn't accessible, add yourself to the kvm group:

    sudo usermod -aG kvm $USER
    # then log out and back in

Check what's needed:

    test/check-deps.sh

This shows required and optional tools with distro-specific install
hints. The essentials:

A working Python 3 installation with pip is required for virtme-ng.

**Debian/Ubuntu:**

    sudo apt install qemu-system-x86 e2fsprogs xfsprogs quota \
        util-linux cpio rpm2cpio curl kmod file zstd dpkg
    pip install virtme-ng

**Fedora/RHEL:**

    sudo dnf install qemu-system-x86-core e2fsprogs xfsprogs quota \
        util-linux cpio rpm2cpio curl kmod file zstd dpkg
    pip install virtme-ng

### Quick start

From a fresh clone:

    ./configure && make               # build quotatool
    test/run-tests --setup --smoke    # download kernels, smoke test

`--setup` handles everything: downloads busybox, builds initramfs,
downloads vendor kernels, builds rootfs for RHEL kernels.
First run takes a while (mostly kernel downloads).

`--smoke` runs one kernel per boot path (~30 seconds) to verify
the infrastructure works.

### Full test run

    test/run-tests --all              # all kernels
    test/run-tests --kernel debian-12 # single kernel
    test/run-tests --tier 1           # tier 1 only
    test/run-tests --list             # show all kernels and status
    test/run-tests --help             # full list of options

Results are saved to `test/results/`.

### BSD testing

BSD tests run quotatool inside FreeBSD and OpenBSD VMs (QEMU/KVM).
Separate from the Linux tests — different entry point, different
infrastructure.

    test/bsd/check-deps.sh            # verify host tools
    test/bsd/run-tests --setup        # download images, provision VMs
    test/bsd/run-tests --all          # run on FreeBSD + OpenBSD
    test/bsd/run-tests --freebsd      # FreeBSD only
    test/bsd/run-tests --openbsd      # OpenBSD only
    test/bsd/run-tests --all -v       # verbose (show all subtests)
    test/bsd/run-tests --interactive freebsd  # SSH into VM with quotas

First run downloads ~660MB (FreeBSD image) and installs OpenBSD
from CD (~300MB). Subsequent runs use provisioned snapshots (~15s boot).

### Troubleshooting

If a test fails, run the failing kernel with `--verbose`:

    test/run-tests --kernel <name> --verbose

## License
This software is available under the terms of the GNU General Public License (GPL) 2.0 or any later version.
