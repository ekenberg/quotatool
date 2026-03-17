quotatool
=========

> **Branch `m1-testing` — development branch, not for production use.**
> See [Testing](#testing) below for how to run the multi-kernel test suite.

![Quotatool](http://quotatool.ekenberg.se/diskusage.gif) Commandline utility for filesystem quotas on Linux, Mac OS X, FreeBSD, OpenBSD, NetBSD, Solaris and AIX

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

### Mac OS X

* MacPorts
    `sudo port sync; sudo port install quotatool`
* Homebrew
    `brew update; brew install quotatool`

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

The actual arguments accepted depends on your system.  Solaris,
for example, doesn't support group quotas, so the -g option is
useless.   If your getopt() doesn't support optional arguments,
then you always need to pass an argument to -u and -g.


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

   -R      Raise only - makes sure you don't accidentally lower quotas for a user/group

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

BSD-note: According to 'man quotactl', global grace periods should be supported on BSD.
quotatool on BSD does the right thing, which can be confirmed with 'edquota -t'.
However, the value doesn't seem to be used by the system when usage passes a soft limit.

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

-- Mac OS X --

-- BSD --
FreeBSD, OpenBSD, NetBSD (ufs, ffs)

-- Solaris --

-- AIX --

Missing your favorite *nix OS? Missing a feature, or found a bug?
Feel free to add an Issue on https://github.com/ekenberg/quotatool

## Testing

quotatool has a multi-kernel test suite that boots vendor kernels in
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

    ./configure && make                  # build quotatool
    test/run-tests --setup --smoke    # download kernels, smoke test

`--setup` handles everything: downloads busybox, builds initramfs,
downloads vendor kernels, builds rootfs for RHEL kernels.
First run takes a while (mostly kernel downloads).

`--smoke` runs one kernel per boot path (~30 seconds) to verify
the infrastructure works.

### Full test run

    test/run-tests --all               # all kernels
    test/run-tests --kernel debian-12 # single kernel
    test/run-tests --tier 1           # tier 1 only
    test/run-tests --list             # show all kernels and status

Results are saved to `test/results/`.

### Troubleshooting

If a smoke test fails, run the failing kernel with `--verbose`:

    test/run-tests --kernel <name> --verbose

**qemu+9p failures on newer hosts**: The qemu+9p path runs host
binaries inside old kernels. If your host glibc is newer than the
test kernel supports (glibc 2.40+ needs kernel >= 4.4), old kernels
will fail with "kernel too old". This only affects tier 2-3 legacy
kernels (< 4.4). Use `--list` to check compatibility.

## License
This software is available under the terms of the GNU General Public License (GPL) 2.0 or any later version.
