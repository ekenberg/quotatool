# Test Framework Dependencies

Packages needed to run the quotatool multi-kernel test framework.

## Required (all testing)

| Package            | What for                                    | RHEL/Fedora              |
|--------------------|---------------------------------------------|--------------------------|
| qemu-system-x86    | VM boot (the core of everything)            | `qemu-system-x86-core`   |
| virtme-ng          | Kernel boot wrapper (modern path)           | `pip install virtme-ng`  |
| e2fsprogs          | mkfs.ext4, quotacheck                       | `e2fsprogs`              |
| xfsprogs           | mkfs.xfs                                    | `xfsprogs`               |
| quota              | quotaon, quotaoff, repquota                 | `quota`                  |
| util-linux         | losetup, mount (usually pre-installed)      | `util-linux`             |
| coreutils          | truncate, timeout (usually pre-installed)   | `coreutils`              |

## Required (kernel downloads, Phase 3)

| Package            | What for                                    | RHEL/Fedora              |
|--------------------|---------------------------------------------|--------------------------|
| rpm2cpio + cpio    | Extract vmlinuz from RPM packages           | `rpm` + `cpio`           |
| dpkg-deb           | Extract vmlinuz from DEB packages           | `dpkg`                   |
| curl or wget       | Download kernel packages                    | `curl`                   |

## Strongly recommended

| Package            | What for                                    | RHEL/Fedora              |
|--------------------|---------------------------------------------|--------------------------|
| KVM (`/dev/kvm`)   | Hardware-accelerated VMs (~100x faster)     | kernel module + group    |

### Enabling KVM

```bash
# Check if KVM is available
ls -la /dev/kvm

# If missing, load the module (Intel or AMD)
sudo modprobe kvm_intel  # or kvm_amd

# Add yourself to the kvm group
sudo usermod -aG kvm $USER
# (log out and back in for group change to take effect)
```

**Note on VPS/cloud**: KVM requires nested virtualization support from
the hypervisor. Many VPS providers don't enable this. Without KVM, QEMU
falls back to software emulation — functional but extremely slow (~100x).
Check with `grep -E 'vmx|svm' /proc/cpuinfo`.

## virtme-ng installation

virtme-ng is a Python tool. Install via pip:

```bash
pip install virtme-ng
# or
pipx install virtme-ng
```

Requires Python 3.8+. The `vng` command must be in PATH.

## Quick check

```bash
# Verify everything is available:
command -v qemu-system-x86_64 && echo "qemu: ok"
command -v vng && echo "virtme-ng: ok"
command -v mkfs.ext4 && echo "e2fsprogs: ok"
command -v mkfs.xfs && echo "xfsprogs: ok"
command -v repquota && echo "quota: ok"
command -v losetup && echo "util-linux: ok"
[[ -r /dev/kvm ]] && echo "KVM: ok" || echo "KVM: NOT available (will be slow)"
```
