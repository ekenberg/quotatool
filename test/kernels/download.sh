#!/bin/bash
# download.sh — Fetch and extract kernels for the test matrix.
#
# Reads kernels.conf, downloads kernel packages, extracts vmlinuz + modules.
# Idempotent: skips kernels that are already extracted.
#
# Usage:
#   ./download.sh                  # download all kernels
#   ./download.sh --tier 1         # download tier 1 only
#   ./download.sh --kernel mainline-5.4  # download one kernel
#   ./download.sh --list           # show matrix without downloading
#   ./download.sh --force          # re-download even if already present
#   ./download.sh --clean          # remove all downloaded kernels
#
# Requirements: curl, dpkg-deb (for .deb), rpm2cpio + cpio (for .rpm)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/kernels.conf"
PPA_BASE="https://kernel.ubuntu.com/mainline"

# Colors (if terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die()  { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }
info() { echo -e "${BLUE}>>>${NC} $*"; }
ok()   { echo -e "${GREEN}OK${NC} $*"; }
warn() { echo -e "${YELLOW}WARN${NC} $*"; }
skip() { echo -e "  ${YELLOW}SKIP${NC} $*"; }

# Parse kernels.conf, emit: name|version|boot_method|tier|source
# Skips comments and blank lines.
parse_conf() {
    grep -v '^\s*#' "$CONF" | grep -v '^\s*$' | while IFS='|' read -r name version boot tier source; do
        # Trim whitespace
        name=$(echo "$name" | xargs)
        version=$(echo "$version" | xargs)
        boot=$(echo "$boot" | xargs)
        tier=$(echo "$tier" | xargs)
        source=$(echo "$source" | xargs)
        [[ -z "$name" ]] && continue
        echo "$name|$version|$boot|$tier|$source"
    done
}

# Check if a kernel is already extracted (vmlinuz exists).
is_extracted() {
    local name="$1"
    [[ -n "$(find_vmlinuz "$name")" ]]
}

# Find the vmlinuz path for an extracted kernel.
# Checks multiple locations:
#   /boot/vmlinu*              — Debian <=12, Ubuntu, CentOS 6/7, openSUSE
#   /lib/modules/*/vmlinuz     — EL8+, Fedora 30+
#   /usr/lib/modules/*/vmlinuz — Debian 13+ (usrmerge)
find_vmlinuz() {
    local name="$1"
    local dir="$SCRIPT_DIR/$name/extracted"
    # Try /boot first (most common)
    ls "$dir"/boot/vmlinu* 2>/dev/null | head -1 && return
    # EL8+, Fedora: vmlinuz inside /lib/modules/<ver>/
    find "$dir/lib/modules" -maxdepth 2 -name "vmlinuz" 2>/dev/null | head -1 && return
    # Debian 13+: usrmerge puts modules under /usr/lib/modules/
    find "$dir/usr/lib/modules" -maxdepth 2 -name "vmlinuz" 2>/dev/null | head -1
}

# Ensure /lib/modules/ symlink exists for usrmerge packages (Debian 13+).
# virtme-ng needs modules at /lib/modules/<ver>/ — create a symlink
# if the package only has /usr/lib/modules/.
fixup_usrmerge() {
    local name="$1"
    local dir="$SCRIPT_DIR/$name/extracted"
    if [[ -d "$dir/usr/lib/modules" && ! -d "$dir/lib/modules" ]]; then
        mkdir -p "$dir/lib"
        ln -sf "$dir/usr/lib/modules" "$dir/lib/modules"
    fi
}

# ---------------------------------------------------------------------------
# PPA download
# ---------------------------------------------------------------------------

# Download a kernel from the Ubuntu mainline PPA.
#
# Scrapes the PPA directory index to discover .deb filenames.
# Two package eras:
#   Pre-4.18: single linux-image-*-generic_*_amd64.deb
#   4.18+:    linux-image-unsigned-*-generic + linux-modules-*-generic
#
# Args: $1=kernel name, $2=PPA directory (e.g., "v4.18")
download_ppa() {
    local name="$1"
    local ppa_dir="$2"
    local dest="$SCRIPT_DIR/$name"
    local url="${PPA_BASE}/${ppa_dir}/"

    info "Fetching PPA index: $url"

    local index
    index=$(curl -fsSL "$url") || die "Failed to fetch PPA index: $url"

    # Extract all amd64 .deb links.
    # PPA layouts:
    #   Old (pre-5.x):  files in root dir, href="linux-image-*.deb"
    #   New (5.x+):     files in amd64/ subdir, href="amd64/linux-image-*.deb"
    local all_debs
    all_debs=$(echo "$index" | grep -oP 'href="[^"]*_amd64\.deb"' \
               | sed 's/href="//; s/"//' | sort -u)

    if [[ -z "$all_debs" ]]; then
        die "No amd64 .deb files found at $url"
    fi

    # Strategy: try new-style first (unsigned image + modules), fall back to old-style
    # The href may include a path prefix (e.g., "amd64/"), which we keep for URLs
    # but strip for local filenames.
    local image_href="" modules_href=""

    # New style (4.18+): linux-image-unsigned-*-generic + linux-modules-*-generic
    image_href=$(echo "$all_debs" | grep 'linux-image-unsigned-.*-generic_' | head -1 || true)
    if [[ -n "$image_href" ]]; then
        modules_href=$(echo "$all_debs" | grep 'linux-modules-.*-generic_' | head -1 || true)
    fi

    # Old style (pre-4.18): linux-image-*-generic (not unsigned)
    if [[ -z "$image_href" ]]; then
        image_href=$(echo "$all_debs" | grep 'linux-image-[0-9].*-generic_' | head -1 || true)
    fi

    if [[ -z "$image_href" ]]; then
        die "Could not find linux-image .deb in PPA index at $url"
    fi

    mkdir -p "$dest"

    # Download image package (use basename for local file, full href for URL)
    local image_url="${url}${image_href}"
    local image_basename
    image_basename=$(basename "$image_href")
    local image_file="$dest/$image_basename"
    if [[ ! -f "$image_file" ]]; then
        info "  Downloading: $image_basename"
        curl -fSL -o "$image_file" "$image_url" \
            || die "Failed to download $image_url"
    else
        skip "$image_basename (already downloaded)"
    fi

    # Download modules package (if separate)
    local modules_file=""
    if [[ -n "$modules_href" ]]; then
        local modules_url="${url}${modules_href}"
        local modules_basename
        modules_basename=$(basename "$modules_href")
        modules_file="$dest/$modules_basename"
        if [[ ! -f "$modules_file" ]]; then
            info "  Downloading: $modules_basename"
            curl -fSL -o "$modules_file" "$modules_url" \
                || die "Failed to download $modules_url"
        else
            skip "$modules_basename (already downloaded)"
        fi
    fi

    # Record source URLs for reproducibility
    {
        echo "# Downloaded $(date -Iseconds)"
        echo "image=$image_url"
        [[ -n "$modules_href" ]] && echo "modules=${url}${modules_href}"
    } > "$dest/SOURCE_URLS"

    # Extract
    info "  Extracting: $image_basename"
    mkdir -p "$dest/extracted"
    dpkg-deb -x "$image_file" "$dest/extracted"

    if [[ -n "$modules_file" && -f "$modules_file" ]]; then
        local modules_basename
        modules_basename=$(basename "$modules_file")
        info "  Extracting: $modules_basename"
        dpkg-deb -x "$modules_file" "$dest/extracted"
    fi

    # Fix usrmerge layout (Debian 13+)
    fixup_usrmerge "$name"

    # Verify vmlinuz exists
    local vmlinuz
    vmlinuz=$(find_vmlinuz "$name")
    if [[ -z "$vmlinuz" ]]; then
        die "Extraction succeeded but no vmlinuz found in $dest/extracted/boot/"
    fi

    ok "$name: $(basename "$vmlinuz")"
}

# ---------------------------------------------------------------------------
# RPM download
# ---------------------------------------------------------------------------

# Download kernel from direct RPM URL(s).
# Args: $1=kernel name, $2=comma-separated RPM URL(s)
download_rpm() {
    local name="$1"
    local urls="$2"
    local dest="$SCRIPT_DIR/$name"

    # Check for rpm2cpio
    if ! command -v rpm2cpio >/dev/null 2>&1; then
        die "rpm2cpio not found — needed for RPM extraction"
    fi

    mkdir -p "$dest" "$dest/extracted"

    # Record URLs
    echo "# Downloaded $(date -Iseconds)" > "$dest/SOURCE_URLS"

    local IFS=','
    for url in $urls; do
        url=$(echo "$url" | xargs)  # trim
        local filename
        filename=$(basename "$url")

        local filepath="$dest/$filename"
        if [[ ! -f "$filepath" ]]; then
            info "  Downloading: $filename"
            curl -fSL -o "$filepath" "$url" \
                || die "Failed to download $url"
        else
            skip "$filename (already downloaded)"
        fi

        echo "rpm=$url" >> "$dest/SOURCE_URLS"

        # Extract
        info "  Extracting: $filename"
        (cd "$dest/extracted" && rpm2cpio "$filepath" | cpio -idm --quiet 2>/dev/null)
    done

    fixup_usrmerge "$name"

    # Verify
    local vmlinuz
    vmlinuz=$(find_vmlinuz "$name")
    if [[ -z "$vmlinuz" ]]; then
        die "Extraction succeeded but no vmlinuz found in $dest/extracted/boot/"
    fi

    ok "$name: $(basename "$vmlinuz")"
}

# ---------------------------------------------------------------------------
# DEB download (direct URLs, not PPA scrape)
# ---------------------------------------------------------------------------

# Download kernel from direct .deb URL(s).
# Args: $1=kernel name, $2=comma-separated .deb URL(s)
download_deb() {
    local name="$1"
    local urls="$2"
    local dest="$SCRIPT_DIR/$name"

    mkdir -p "$dest" "$dest/extracted"

    echo "# Downloaded $(date -Iseconds)" > "$dest/SOURCE_URLS"

    local IFS=','
    for url in $urls; do
        url=$(echo "$url" | xargs)
        local filename
        filename=$(basename "$url")

        local filepath="$dest/$filename"
        if [[ ! -f "$filepath" ]]; then
            info "  Downloading: $filename"
            curl -fSL -o "$filepath" "$url" \
                || die "Failed to download $url"
        else
            skip "$filename (already downloaded)"
        fi

        echo "deb=$url" >> "$dest/SOURCE_URLS"

        info "  Extracting: $filename"
        dpkg-deb -x "$filepath" "$dest/extracted"
    done

    fixup_usrmerge "$name"

    local vmlinuz
    vmlinuz=$(find_vmlinuz "$name")
    if [[ -z "$vmlinuz" ]]; then
        die "Extraction succeeded but no vmlinuz found in $dest/extracted/boot/"
    fi

    ok "$name: $(basename "$vmlinuz")"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

# Download one kernel entry.
# Args: $1=name, $2=version, $3=boot_method, $4=tier, $5=source
download_one() {
    local name="$1" version="$2" boot="$3" tier="$4" source="$5"

    local source_type="${source%%:*}"
    local source_ref="${source#*:}"

    case "$source_type" in
        ppa)
            download_ppa "$name" "$source_ref"
            ;;
        rpm)
            download_rpm "$name" "$source_ref"
            ;;
        deb)
            download_deb "$name" "$source_ref"
            ;;
        unavailable)
            warn "$name: source not yet available (see kernels.conf TODO)"
            return 0
            ;;
        *)
            die "$name: unknown source type '$source_type'"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_list() {
    printf "${BOLD}%-20s %-8s %-8s %-5s %-12s %s${NC}\n" \
        "NAME" "VERSION" "BOOT" "TIER" "SOURCE" "STATUS"
    echo "------------------------------------------------------------------------"
    parse_conf | while IFS='|' read -r name version boot tier source; do
        local source_type="${source%%:*}"
        local status
        if is_extracted "$name"; then
            status="${GREEN}extracted${NC}"
        elif [[ "$source_type" == "unavailable" ]]; then
            status="${YELLOW}unavailable${NC}"
        else
            status="${RED}not downloaded${NC}"
        fi
        printf "%-20s %-8s %-8s %-5s %-12s " "$name" "$version" "$boot" "$tier" "$source_type"
        echo -e "$status"
    done
}

cmd_download() {
    local filter_tier="${OPT_TIER:-}"
    local filter_kernel="${OPT_KERNEL:-}"
    local force="${OPT_FORCE:-0}"
    local count=0 downloaded=0 skipped=0 unavail=0 failed=0

    parse_conf | while IFS='|' read -r name version boot tier source; do
        count=$((count + 1))

        # Filter by tier
        if [[ -n "$filter_tier" && "$tier" != "$filter_tier" ]]; then
            continue
        fi

        # Filter by kernel name
        if [[ -n "$filter_kernel" && "$name" != "$filter_kernel" ]]; then
            continue
        fi

        local source_type="${source%%:*}"

        # Skip unavailable
        if [[ "$source_type" == "unavailable" ]]; then
            warn "$name: not yet available"
            unavail=$((unavail + 1))
            continue
        fi

        # Skip already extracted (unless --force)
        if [[ "$force" != "1" ]] && is_extracted "$name"; then
            skip "$name (already extracted, use --force to re-download)"
            skipped=$((skipped + 1))
            continue
        fi

        # Force: remove existing extraction
        if [[ "$force" == "1" && -d "$SCRIPT_DIR/$name/extracted" ]]; then
            rm -rf "$SCRIPT_DIR/$name/extracted"
        fi

        info "Downloading: ${BOLD}$name${NC} (kernel $version, tier $tier)"
        # Don't let individual failures stop the whole batch
        set +e
        download_one "$name" "$version" "$boot" "$tier" "$source"
        local rc=$?
        set -e
        if [[ $rc -eq 0 ]]; then
            downloaded=$((downloaded + 1))
        else
            warn "$name: download failed (exit $rc)"
            failed=$((failed + 1))
        fi
    done

    echo ""
    info "Done."
}

cmd_clean() {
    info "Removing all downloaded kernels..."
    parse_conf | while IFS='|' read -r name version boot tier source; do
        if [[ -d "$SCRIPT_DIR/$name" ]]; then
            info "  Removing: $name"
            rm -rf "$SCRIPT_DIR/$name"
        fi
    done
    ok "Clean complete."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Download and extract kernels for the quotatool test matrix.

Options:
  --tier N        Only download kernels of tier N (1, 2, or 3)
  --kernel NAME   Only download the named kernel
  --list          Show matrix status without downloading
  --force         Re-download and re-extract even if present
  --clean         Remove all downloaded kernels
  -h, --help      Show this help

Reads: $(basename "$CONF")
EOF
}

OPT_TIER=""
OPT_KERNEL=""
OPT_FORCE="0"
CMD="download"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)   OPT_TIER="$2"; shift 2 ;;
        --kernel) OPT_KERNEL="$2"; shift 2 ;;
        --list)   CMD="list"; shift ;;
        --force)  OPT_FORCE="1"; shift ;;
        --clean)  CMD="clean"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

if [[ ! -f "$CONF" ]]; then
    die "kernels.conf not found at $CONF"
fi

case "$CMD" in
    list)     cmd_list ;;
    download) cmd_download ;;
    clean)    cmd_clean ;;
esac
