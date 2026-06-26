#!/usr/bin/env bash
#
# install-fcscli.sh — Install FCSCLI from a local download
#
# PURPOSE
#   Extracts and installs a previously downloaded FCSCLI archive.
#   The FCS CLI binary is not publicly downloadable; it requires
#   authentication through the Falcon Console. This script handles
#   extraction and PATH installation once you have the archive.
#
# USAGE
#   ./scripts/install-fcscli.sh [OPTIONS]
#
# OPTIONS
#   -v, --version VERSION    FCSCLI version to look for (default: 2.2.0)
#   -o, --os OS             Target OS: linux, darwin, windows
#   -a, --arch ARCH         Target architecture: amd64, arm64
#   -d, --dir DIR           Installation directory (default: /usr/local/bin)
#   -h, --help              Show this help
#
# EXAMPLES
#   # Auto-detect platform
#   ./scripts/install-fcscli.sh
#
#   # macOS Apple Silicon, explicit
#   ./scripts/install-fcscli.sh --os darwin --arch arm64
#
#   # Specific version, custom install dir
#   ./scripts/install-fcscli.sh --version 2.1.5 --os linux --arch amd64 --dir ~/bin

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERSION="2.2.0"
OS=""
ARCH=""
INSTALL_DIR="/usr/local/bin"

usage() {
    sed -n '/^# USAGE/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# *//'
    exit 1
}

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

detect_platform() {
    if [[ -z "$OS" ]]; then
        case "$(uname -s)" in
            Linux*)              OS="linux";;
            Darwin*)             OS="darwin";;
            MINGW*|MSYS*|CYGWIN*) OS="windows";;
            *)
                log_error "Unsupported OS: $(uname -s)"
                exit 1
                ;;
        esac
        log_info "Detected OS: $OS"
    fi

    if [[ -z "$ARCH" ]]; then
        case "$(uname -m)" in
            x86_64|amd64)  ARCH="amd64";;
            arm64|aarch64) ARCH="arm64";;
            *)
                log_error "Unsupported architecture: $(uname -m)"
                exit 1
                ;;
        esac
        log_info "Detected architecture: $ARCH"
    fi
}

build_filename() {
    local os_name arch_name extension

    case "$OS" in
        darwin)  os_name="Darwin";  extension="tar.gz";;
        linux)   os_name="Linux";   extension="tar.gz";;
        windows) os_name="Windows"; extension="zip";;
    esac

    case "$ARCH" in
        amd64) arch_name="x86_64";;
        arm64) arch_name="arm64";;
    esac

    echo "fcs_${VERSION}_${os_name}_${arch_name}.${extension}"
}

locate_archive() {
    local filename="$1"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    for location in "./${filename}" "$HOME/Downloads/${filename}"; do
        if [[ -f "$location" ]]; then
            log_info "Found archive: $location"
            cp "$location" "${tmp_dir}/"
            echo "$tmp_dir"
            return 0
        fi
    done

    log_warn "Archive not found in current directory or ~/Downloads"
    log_info "Download ${filename} from the Falcon Console:"
    log_info "  1. Go to: https://falcon.crowdstrike.com"
    log_info "  2. Navigate to: Support and resources > Resources and tools > Tool downloads"
    log_info "  3. Search for: FCS CLI"
    log_info "  4. Download: ${filename}"
    log_info "  5. Place the file in the current directory or ~/Downloads"
    echo
    read -r -p "Press Enter after downloading the file..."

    for location in "./${filename}" "$HOME/Downloads/${filename}" "${tmp_dir}/${filename}"; do
        if [[ -f "$location" ]]; then
            cp "$location" "${tmp_dir}/" 2>/dev/null || true
            echo "$tmp_dir"
            return 0
        fi
    done

    log_error "Archive still not found. Please download ${filename} and retry."
    rm -rf "$tmp_dir"
    exit 1
}

install_fcs() {
    local tmp_dir="$1"
    local filename="$2"

    log_info "Extracting archive..."
    cd "$tmp_dir"

    if [[ "$filename" == *.tar.gz ]]; then
        tar -xzf "$filename"
    elif [[ "$filename" == *.zip ]]; then
        unzip -q "$filename"
    fi

    local binary_name="fcs"
    [[ "$OS" == "windows" ]] && binary_name="fcs.exe"

    if [[ ! -f "$binary_name" ]]; then
        log_error "Binary not found after extraction: $binary_name"
        exit 1
    fi

    chmod +x "$binary_name"
    log_info "Installing to ${INSTALL_DIR}/${binary_name}..."

    if [[ -w "$INSTALL_DIR" ]]; then
        mv "$binary_name" "${INSTALL_DIR}/"
    else
        sudo mv "$binary_name" "${INSTALL_DIR}/"
    fi

    cd - > /dev/null
    rm -rf "$tmp_dir"
    log_success "FCSCLI installed to ${INSTALL_DIR}/${binary_name}"
}

verify_installation() {
    if ! command -v fcs &> /dev/null; then
        log_error "'fcs' not found in PATH. Add ${INSTALL_DIR} to your PATH and retry."
        exit 1
    fi
    local installed_version
    installed_version=$(fcs --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    log_success "FCSCLI version: $installed_version"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version) VERSION="$2"; shift 2;;
        -o|--os)      OS="$2";      shift 2;;
        -a|--arch)    ARCH="$2";    shift 2;;
        -d|--dir)     INSTALL_DIR="$2"; shift 2;;
        -h|--help)    usage;;
        *) log_error "Unknown option: $1"; usage;;
    esac
done

main() {
    log_info "FCSCLI Installation Script"
    echo

    detect_platform

    if command -v fcs &> /dev/null; then
        local current
        current=$(fcs --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        log_info "FCSCLI is already installed (version: $current)"
        read -r -p "Replace with version ${VERSION}? [y/N] " -n 1
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "Installation cancelled."; exit 0; }
    fi

    local filename
    filename=$(build_filename)

    local tmp_dir
    tmp_dir=$(locate_archive "$filename")

    install_fcs "$tmp_dir" "$filename"
    verify_installation

    echo
    log_success "Installation complete!"
    echo
    echo "Next steps:"
    echo "  1. Run: fcs configure"
    echo "  2. Enter your Falcon Client ID and Secret"
    echo "  3. Select your Falcon region (us-1, us-2, eu-1, ...)"
    echo "  4. Start scanning: fcs scan image nginx:latest"
    echo
}

main
