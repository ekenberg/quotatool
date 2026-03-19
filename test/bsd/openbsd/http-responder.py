#!/usr/bin/env python3
"""Micro HTTP responder for QEMU guestfwd -cmd: mode.

Reads one HTTP request from stdin, serves the requested file from
the directory specified as argv[1], writes the HTTP response to stdout.
Spawned per-connection by QEMU's guestfwd.

Usage (in QEMU -netdev):
  guestfwd=tcp:10.0.2.2:80-cmd:python3 /path/to/http-responder.py /path/to/serve
"""
import os
import sys

def main():
    serve_dir = sys.argv[1] if len(sys.argv) > 1 else "."

    # Read HTTP request line
    request_line = ""
    try:
        request_line = sys.stdin.readline()
    except Exception:
        pass

    # Skip remaining headers (read until blank line)
    try:
        while True:
            line = sys.stdin.readline()
            if not line or line.strip() == "":
                break
    except Exception:
        pass

    # Parse requested path
    path = "/"
    if request_line:
        parts = request_line.split()
        if len(parts) >= 2:
            path = parts[1]

    # Map to file
    if path == "/":
        path = "/install.conf"

    filepath = os.path.join(serve_dir, path.lstrip("/"))

    # Serve file or 404
    if os.path.isfile(filepath):
        with open(filepath, "rb") as f:
            content = f.read()
        response = (
            f"HTTP/1.0 200 OK\r\n"
            f"Content-Length: {len(content)}\r\n"
            f"Content-Type: application/octet-stream\r\n"
            f"Connection: close\r\n"
            f"\r\n"
        )
        sys.stdout.buffer.write(response.encode())
        sys.stdout.buffer.write(content)
    else:
        body = f"404 Not Found: {path}\n"
        response = (
            f"HTTP/1.0 404 Not Found\r\n"
            f"Content-Length: {len(body)}\r\n"
            f"Connection: close\r\n"
            f"\r\n"
            f"{body}"
        )
        sys.stdout.buffer.write(response.encode())

    sys.stdout.buffer.flush()

if __name__ == "__main__":
    main()
