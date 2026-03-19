# BSD Test Framework — Host Dependencies

Tools needed on the **Linux host** to run BSD tests in QEMU.
Most are likely already installed from the Linux test framework setup.

## Required

| Tool | Purpose | Debian/Ubuntu | Fedora/RHEL | Arch |
|------|---------|---------------|-------------|------|
| `qemu-system-x86_64` | Run BSD VMs | `qemu-system-x86` | `qemu-system-x86-core` | `qemu-system-x86_64` |
| `qemu-img` | Create CoW disk overlays | `qemu-utils` | `qemu-img` | `qemu-img` |
| `genisoimage` | Build cloud-init seed ISO (FreeBSD) | `genisoimage` | `genisoimage` | `cdrtools` |
| `ssh` / `scp` | File transfer & command execution in VM | `openssh-client` | `openssh-clients` | `openssh` |
| `curl` | Download BSD images | `curl` | `curl` | `curl` |
| `xz` | Decompress .qcow2.xz images | `xz-utils` | `xz` | `xz` |
| `python3` | OpenBSD setup automation (QEMU monitor control) | `python3` | `python3` | `python` |
| `mtools` | Create FAT floppy images (OpenBSD setup, optional) | `mtools` | `mtools` | `mtools` |
| `/dev/kvm` | Hardware acceleration (without this, VMs are painfully slow) | — | — | — |

## Quick Install

**Debian/Ubuntu:**
```
sudo apt install qemu-system-x86 qemu-utils genisoimage openssh-client curl xz-utils
```

**Fedora/RHEL:**
```
sudo dnf install qemu-system-x86-core qemu-img genisoimage openssh-clients curl xz
```

**Arch:**
```
sudo pacman -S qemu-system-x86_64 qemu-img cdrtools openssh curl xz
```

## KVM Access

You need read/write access to `/dev/kvm`:
```
sudo usermod -aG kvm $USER
```
Then log out and back in. Verify: `test -w /dev/kvm && echo OK`

## Verify

Run `test/bsd/check-deps.sh` to confirm everything is in place.
