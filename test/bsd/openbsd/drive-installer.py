#!/usr/bin/env python3
"""Drive OpenBSD installer via serial console.

Spawns QEMU as a subprocess, reads its serial output, and sends
answers to installer prompts at the right time.

Usage:
    python3 drive-installer.py <ssh-pubkey-file> <disk-image> <iso> [ssh-port]
"""
import os
import re
import subprocess
import sys
import threading
import time


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def main():
    if len(sys.argv) < 4:
        log("Usage: drive-installer.py <ssh-pubkey> <disk> <iso> [ssh-port]")
        sys.exit(1)

    pubkey_file = sys.argv[1]
    disk_image = sys.argv[2]
    iso = sys.argv[3]
    ssh_port = sys.argv[4] if len(sys.argv) > 4 else "2223"

    pubkey = open(pubkey_file).read().strip()

    # Answer rules: (prompt_substring, answer, max_uses)
    # max_uses=0 means unlimited
    rules = [
        # Boot prompt — redirect kernel output to serial console.
        # Sends multiple commands with pauses (list = multi-step).
        ("boot>", ["stty com0 115200\n", "set tty com0\n", "boot\n"], 1),
        # Initial choice
        ("(I)nstall", "I\n", 1),
        # Keyboard layout
        ("Choose your keyboard layout", "default\n", 1),
        # Hostname
        ("System hostname", "openbsd-test\n", 1),
        # Network
        ("Which network interface", "vio0\n", 1),
        ("IPv4 address for vio0", "dhcp\n", 1),
        ("IPv6 address for vio0", "none\n", 1),
        ("DNS domain name", "localdomain\n", 1),
        # Root password — asked twice (enter + confirm)
        ("Password for root", "quotatool\n", 0),
        # SSH key for root
        ("Public ssh key for root", pubkey + "\n", 1),
        # SSH
        ("Start sshd", "yes\n", 1),
        # X11
        ("Do you expect to run the X Window", "no\n", 1),
        # User setup
        ("Setup a user", "puffy\n", 1),
        ("Full name for user puffy", "puffy\n", 1),
        # User password — asked twice
        ("Password for user puffy", "*************\n", 0),
        ("Public ssh key for user puffy", "\n", 1),
        # Root SSH login
        ("Allow root ssh login", "prohibit-password\n", 1),
        # Timezone
        ("What timezone", "UTC\n", 1),
        # Root disk
        ("Which disk is the root disk", "\n", 1),
        ("Use (W)hole disk", "W\n", 1),
        ("Use (A)uto layout", "A\n", 1),
        # Sets — first time: select HTTP and server
        ("Location of sets", "http\n", 1),
        ("HTTP proxy URL", "none\n", 1),
        ("HTTP Server", "cdn.openbsd.org\n", 1),
        ("Server directory", "pub/OpenBSD/7.8/amd64\n", 1),
        # Set selection
        ("Set name", "-game*.tgz -x*.tgz\n", 1),
        ("Continue without verification", "yes\n", 0),
        # After sets installed, asks for more sets
        ("Location of sets", "done\n", 1),
        # Completion
        ("CONGRATULATIONS", None, 1),
    ]

    used = [0] * len(rules)

    # Start QEMU
    qemu_cmd = [
        "qemu-system-x86_64", "-enable-kvm", "-m", "2G", "-smp", "2",
        "-drive", f"file={disk_image},media=disk,if=virtio",
        "-cdrom", iso,
        "-boot", "d",
        "-device", "e1000,netdev=net0",
        "-netdev", f"user,id=net0,hostfwd=tcp::{ssh_port}-:22",
        "-nographic",
    ]

    log(f"[installer] Starting QEMU...")
    proc = subprocess.Popen(
        qemu_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )

    buf = ""
    install_complete = False
    start_time = time.time()
    timeout = 600  # 10 minutes

    log("[installer] Monitoring serial output...")

    try:
        while True:
            elapsed = time.time() - start_time
            if elapsed > timeout:
                log(f"[installer] TIMEOUT after {int(elapsed)}s")
                proc.terminate()
                sys.exit(1)

            if install_complete:
                time.sleep(3)
                break

            # Read one byte at a time (non-buffered)
            byte = proc.stdout.read(1)
            if not byte:
                log("[installer] QEMU stdout closed")
                break

            char = byte.decode("utf-8", errors="replace")
            sys.stderr.write(char)
            sys.stderr.flush()
            buf += char

            # Check buffer against rules
            for i, (prompt, answer, max_uses) in enumerate(rules):
                if prompt not in buf:
                    continue
                if max_uses > 0 and used[i] >= max_uses:
                    continue

                used[i] += 1

                if answer is None:
                    log("\n[installer] Installation complete!")
                    install_complete = True
                    break

                time.sleep(0.3)
                log(f"\n[installer] '{prompt}' → sending answer")
                if isinstance(answer, list):
                    # Multi-step: send each part with a delay
                    for part in answer:
                        proc.stdin.write(part.encode())
                        proc.stdin.flush()
                        time.sleep(1.0)
                else:
                    proc.stdin.write(answer.encode())
                    proc.stdin.flush()
                buf = ""
                break

            # Prevent buffer overflow
            if len(buf) > 8192:
                buf = buf[-4096:]

    finally:
        log(f"\n[installer] Terminating QEMU (PID {proc.pid})...")
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()

    elapsed = int(time.time() - start_time)
    if install_complete:
        log(f"[installer] Done successfully ({elapsed}s)")
        sys.exit(0)
    else:
        log(f"[installer] Ended without completion ({elapsed}s)")
        sys.exit(1)


if __name__ == "__main__":
    main()
