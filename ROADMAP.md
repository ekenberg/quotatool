# Roadmap

## v1.7.0 — Quality Release

Bug fixes verified by a comprehensive new test suite.
**No platform changes** — all existing platforms continue to be supported.

What's in it:
- Multi-kernel test framework (25 Linux kernels, ext4 + XFS)
- Bug fixes: +0M clearing quota, timespan validation, grace period
  display, XFS grace reset, unused header removal
- Clean compile with `-Wall -Wextra` on gcc and clang
- Dead code removal

What's NOT in it:
- No platform drops (that's v1.8.0)
- No new features (quotactl_fd, project quotas — that's v1.8.0+)

## v1.8.0 — Platform Changes

Drops platforms that no longer have working quota infrastructure.
Adds BSD test coverage for the platforms we keep.

Planned changes:
- **Drop**: macOS (APFS has no quotactl), AIX, Solaris (ZFS has its
  own quota system), NetBSD (incompatible quotactl API change)
- **Keep**: Linux, FreeBSD, OpenBSD
- BSD test coverage (FreeBSD, OpenBSD)
- Possibly: `quotactl_fd()` support (tmpfs/bcachefs quotas, kernel 5.14+)
- Possibly: project quotas `-p` flag (XFS, ext4 4.4+)

**macOS/Homebrew users**: v1.7.x maintenance releases will continue
to receive bug fixes after v1.8.0 ships.

## v1.7.x — Maintenance

Bug fixes backported to the `release-1.7` branch. For users who
can't upgrade to v1.8.0 (which drops platforms).
