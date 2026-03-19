#!/bin/bash
# Wrapper for http-responder.py — called by QEMU guestfwd -cmd:
# Takes the serve directory from the same location as this script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVE_DIR="${QUOTATOOL_OPENBSD_SERVE_DIR:-$SCRIPT_DIR/../images/openbsd-serve}"
exec python3 "$SCRIPT_DIR/http-responder.py" "$SERVE_DIR"
