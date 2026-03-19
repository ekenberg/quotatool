# Roadmap

## v1.8.0 — Platform Changes

Drops platforms that no longer have working quota infrastructure.
Adds BSD test coverage for the platforms that remain.

Changes:
- **Dropped**: macOS (APFS has no quotactl), AIX (proprietary JFS2
  extensions), Solaris (ZFS has its own quota system), NetBSD
  (replaced quotactl with incompatible libquota in 6.0)
- **Kept**: Linux, FreeBSD, OpenBSD
- BSD test coverage (FreeBSD 14.4, OpenBSD 7.8)

See [PLATFORM-CHANGES.md](PLATFORM-CHANGES.md) for detailed rationale
and references for each platform decision.

**macOS/Homebrew users**: v1.7.x continues to build on macOS and will
receive bug fixes.

## Future

Planned for future releases:
- `quotactl_fd()` support (tmpfs/bcachefs quotas, kernel 5.14+)
- Project quotas `-p` flag (XFS, ext4 4.4+)

## v1.7.x — Maintenance

Bug fixes backported to the v1.7.x line. For users who can't upgrade
to v1.8.0.

## v1.7.0 — Quality Release

Bug fixes verified by a comprehensive new test suite.
**No platform changes** — all existing platforms continue to be supported.

What's in it:
- Multi-kernel test framework (25+ Linux kernels, ext4 + XFS)
- Bug fixes and code cleanup

What's NOT in it:
- No platform drops (that's v1.8.0)
- No new features (quotactl_fd, project quotas — that's v1.8.0+)
