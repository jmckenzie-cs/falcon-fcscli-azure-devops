#!/usr/bin/env bash
#
# download-fcscli.sh — Download FCSCLI via the CrowdStrike API
#
# PURPOSE
#   Authenticates against the CrowdStrike API, fetches the latest FCSCLI
#   binary for the current platform, verifies its SHA-256 hash, and saves
#   it to the current directory. Use this in CI/CD pipelines where you want
#   a fresh download on each run.
#
# USAGE
#   ./scripts/download-fcscli.sh
#
# REQUIRED ENVIRONMENT VARIABLES
#   FALCON_CLIENT_ID      — CrowdStrike OAuth2 Client ID
#   FALCON_CLIENT_SECRET  — CrowdStrike OAuth2 Client Secret
#
# OPTIONAL ENVIRONMENT VARIABLES
#   FALCON_API_URL        — API base URL (default: https://api.crowdstrike.com)
#                           Set to your regional endpoint if needed:
#                             us-1: https://api.crowdstrike.com
#                             us-2: https://api.us-2.crowdstrike.com
#                             eu-1: https://api.eu-1.crowdstrike.com
#   FCS_TARGET_OS         — Override OS detection: linux, darwin
#   FCS_TARGET_ARCH       — Override arch detection: amd64, arm64
#   OUTPUT_DIR            — Directory to save the downloaded archive (default: .)
#
# EXAMPLES
#   # Standard usage — credentials from environment
#   export FALCON_CLIENT_ID="your-client-id"
#   export FALCON_CLIENT_SECRET="your-client-secret"
#   ./scripts/download-fcscli.sh
#
#   # EU region
#   export FALCON_API_URL="https://api.eu-1.crowdstrike.com"
#   ./scripts/download-fcscli.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FALCON_CLIENT_ID="${FALCON_CLIENT_ID:-}"
FALCON_CLIENT_SECRET="${FALCON_CLIENT_SECRET:-}"
FALCON_API_URL="${FALCON_API_URL:-https://api.crowdstrike.com}"
FCS_TARGET_OS="${FCS_TARGET_OS:-}"
FCS_TARGET_ARCH="${FCS_TARGET_ARCH:-}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()
    command -v curl &> /dev/null || missing+=("curl")
    command -v jq   &> /dev/null || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    if [[ -z "$FALCON_CLIENT_ID" ]] || [[ -z "$FALCON_CLIENT_SECRET" ]]; then
        log_error "FALCON_CLIENT_ID and FALCON_CLIENT_SECRET must be set"
        exit 1
    fi

    log_success "Prerequisites OK"
}

detect_platform() {
    if [[ -z "$FCS_TARGET_OS" ]]; then
        case "$(uname -s)" in
            Linux*)  FCS_TARGET_OS="linux";;
            Darwin*) FCS_TARGET_OS="darwin";;
            *)
                log_error "Unsupported OS: $(uname -s)"
                exit 1
                ;;
        esac
    fi

    if [[ -z "$FCS_TARGET_ARCH" ]]; then
        case "$(uname -m)" in
            x86_64|amd64)  FCS_TARGET_ARCH="amd64";;
            arm64|aarch64) FCS_TARGET_ARCH="arm64";;
            *)
                log_error "Unsupported architecture: $(uname -m)"
                exit 1
                ;;
        esac
    fi

    log_info "Target platform: ${FCS_TARGET_OS}/${FCS_TARGET_ARCH}"
}

get_access_token() {
    log_info "Authenticating with CrowdStrike API..."

    local response
    response=$(curl --silent --request POST \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${FALCON_CLIENT_ID}" \
        --data-urlencode "client_secret=${FALCON_CLIENT_SECRET}" \
        --url "${FALCON_API_URL}/oauth2/token")

    local token
    token=$(echo "$response" | jq -r '.access_token')

    if [[ "$token" == "null" ]] || [[ -z "$token" ]]; then
        log_error "Authentication failed. Response: $response"
        exit 1
    fi

    log_success "Authentication successful"
    echo "$token"
}

fetch_download_info() {
    local token="$1"

    log_info "Fetching available FCSCLI versions..."

    local filter="category:\"fcs\"+os:\"${FCS_TARGET_OS}\"+arch:\"${FCS_TARGET_ARCH}\""

    local response
    response=$(curl --silent --get \
        --header "Accept: application/json" \
        --header "Authorization: Bearer ${token}" \
        --url "${FALCON_API_URL}/csdownloads/combined/files-download/v2" \
        --data-urlencode "filter=${filter}")

    # API returns results in chronological order; take the last entry (latest)
    local info
    info=$(echo "$response" | jq -r '.resources[-1]')

    if [[ "$info" == "null" ]] || [[ -z "$info" ]]; then
        log_error "No FCSCLI versions found for ${FCS_TARGET_OS}/${FCS_TARGET_ARCH}"
        log_error "API response: $(echo "$response" | jq '.' 2>/dev/null || echo "$response")"
        exit 1
    fi

    local count
    count=$(echo "$response" | jq -r '.resources | length')
    log_info "Found $count available version(s). Selecting latest."

    echo "$info"
}

download_and_verify() {
    local token="$1"
    local info="$2"

    local file_name file_version file_hash download_url
    file_name=$(echo "$info"     | jq -r '.file_name')
    file_version=$(echo "$info"  | jq -r '.file_version')
    file_hash=$(echo "$info"     | jq -r '.file_hash')
    download_url=$(echo "$info"  | jq -r '.download_info.download_url')

    log_info "Downloading: $file_name  (version $file_version)"
    log_info "Expected SHA-256: $file_hash"

    local output_path="${OUTPUT_DIR}/${file_name}"
    curl --location --progress-bar --output "$output_path" "$download_url"
    log_success "Downloaded: $output_path"

    log_info "Verifying file integrity..."
    local computed
    if command -v sha256sum &> /dev/null; then
        computed=$(sha256sum "$output_path" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        computed=$(shasum -a 256 "$output_path" | awk '{print $1}')
    else
        log_warn "No SHA-256 tool found — skipping integrity check"
        echo "$output_path"
        return
    fi

    if [[ "$computed" == "$file_hash" ]]; then
        log_success "Integrity verified"
    else
        log_error "Hash mismatch! Expected: $file_hash  Got: $computed"
        exit 1
    fi

    echo "$output_path"
}

main() {
    log_info "FCSCLI Programmatic Download Script"
    echo

    check_prerequisites
    detect_platform

    local token
    token=$(get_access_token)

    local info
    info=$(fetch_download_info "$token")

    local downloaded_file
    downloaded_file=$(download_and_verify "$token" "$info")

    echo
    log_success "Download complete: $downloaded_file"
    echo
    echo "Next steps:"
    echo "  tar -xzf $downloaded_file"
    echo "  chmod +x fcs"
    echo "  sudo mv fcs /usr/local/bin/"
    echo "  fcs configure"
    echo
}

main
