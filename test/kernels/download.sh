#!/bin/bash
# download.sh — fetch and extract vendor kernels
# Reads kernels.conf, downloads .deb/.rpm, extracts vmlinuz + modules.
set -euo pipefail
