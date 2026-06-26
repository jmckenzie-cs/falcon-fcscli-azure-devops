#!/usr/bin/env bash
#
# enforce-policy.sh — Fail builds based on FCSCLI scan severity thresholds
#
# PURPOSE
#   Runs an FCSCLI scan and compares finding counts against configurable
#   thresholds. Exits non-zero if any threshold is exceeded, making it
#   suitable as a CI/CD quality gate.
#
# USAGE
#   ./scripts/enforce-policy.sh [OPTIONS] scan <type> <target>
#
# SCAN TYPES
#   image <image-name>      Scan a container image
#   iac <path>              Scan Infrastructure as Code
#
# OPTIONS
#   --severity LEVEL        Minimum severity to evaluate: critical, high, medium, low
#   --max-critical N        Maximum critical findings allowed (default: 0)
#   --max-high N            Maximum high findings allowed (default: 5)
#   --max-medium N          Maximum medium findings allowed (default: 20)
#   --no-fail               Report violations but do not exit non-zero
#   -h, --help              Show this help
#
# ENVIRONMENT VARIABLES (override option defaults)
#   SEVERITY_THRESHOLD      critical | high | medium | low  (default: high)
#   MAX_CRITICAL            integer  (default: 0)
#   MAX_HIGH                integer  (default: 5)
#   MAX_MEDIUM              integer  (default: 20)
#   FAIL_ON_THRESHOLD       true | false  (default: true)
#
# EXAMPLES
#   # Fail on any critical vulnerability in an image
#   ./scripts/enforce-policy.sh scan image nginx:latest --max-critical 0
#
#   # Strict IaC gate — zero critical or high
#   ./scripts/enforce-policy.sh scan iac ./terraform/ --max-critical 0 --max-high 0
#
#   # Warn only, never block the build
#   ./scripts/enforce-policy.sh scan image myapp:latest --no-fail

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SEVERITY_THRESHOLD="${SEVERITY_THRESHOLD:-high}"
MAX_CRITICAL="${MAX_CRITICAL:-0}"
MAX_HIGH="${MAX_HIGH:-5}"
MAX_MEDIUM="${MAX_MEDIUM:-20}"
FAIL_ON_THRESHOLD="${FAIL_ON_THRESHOLD:-true}"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

usage() {
    sed -n '/^# USAGE/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# *//'
    exit 1
}

check_dependencies() {
    for cmd in fcs jq; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "'$cmd' not found. Please install it before running this script."
            exit 1
        fi
    done
}

run_scan() {
    local scan_type="$1"
    local target="$2"
    local output_file
    output_file=$(mktemp --suffix=.json)

    log_info "Running: fcs scan $scan_type $target"

    if fcs scan "$scan_type" "$target" --output json > "$output_file" 2>&1; then
        log_success "Scan completed"
    else
        local code=$?
        log_error "Scan exited with code $code"
        cat "$output_file" >&2
        rm -f "$output_file"
        exit $code
    fi

    echo "$output_file"
}

count_findings() {
    local file="$1"
    local scan_type="$2"
    local field

    if [[ "$scan_type" == "image" ]]; then
        field="vulnerabilities"
    else
        field="issues"
    fi

    local total critical high medium low

    if jq -e ".$field" "$file" &>/dev/null; then
        total=$(jq    ".$field | length" "$file")
        critical=$(jq "[.$field[] | select(.severity==\"CRITICAL\" or .severity==\"Critical\")] | length" "$file")
        high=$(jq     "[.$field[] | select(.severity==\"HIGH\"     or .severity==\"High\")]     | length" "$file")
        medium=$(jq   "[.$field[] | select(.severity==\"MEDIUM\"   or .severity==\"Medium\")]   | length" "$file")
        low=$(jq      "[.$field[] | select(.severity==\"LOW\"      or .severity==\"Low\")]      | length" "$file")
    else
        total=0; critical=0; high=0; medium=0; low=0
    fi

    echo "$total|$critical|$high|$medium|$low"
}

enforce_policy() {
    local total="$1" critical="$2" high="$3" medium="$4" low="$5" target="$6"

    log_info "Policy Enforcement Results: $target"
    echo
    printf "  %-12s %s\n" "Total:"    "$total"
    printf "  %-12s %s  (max allowed: %s)\n" "Critical:" "$critical" "$MAX_CRITICAL"
    printf "  %-12s %s  (max allowed: %s)\n" "High:"     "$high"     "$MAX_HIGH"
    printf "  %-12s %s  (max allowed: %s)\n" "Medium:"   "$medium"   "$MAX_MEDIUM"
    printf "  %-12s %s\n" "Low:"      "$low"
    echo

    local violations=()
    [[ $critical -gt $MAX_CRITICAL ]] && violations+=("CRITICAL: $critical found (max: $MAX_CRITICAL)")
    [[ $high     -gt $MAX_HIGH     ]] && violations+=("HIGH: $high found (max: $MAX_HIGH)")
    [[ $medium   -gt $MAX_MEDIUM   ]] && violations+=("MEDIUM: $medium found (max: $MAX_MEDIUM)")

    if [[ ${#violations[@]} -gt 0 ]]; then
        log_error "Policy violations:"
        for v in "${violations[@]}"; do echo "  ✗ $v" >&2; done
        echo
        if [[ "$FAIL_ON_THRESHOLD" == "true" ]]; then
            log_error "Policy enforcement FAILED"
            return 1
        else
            log_warn "Violations found but --no-fail is set"
            return 0
        fi
    else
        log_success "Policy enforcement PASSED — all thresholds met"
        return 0
    fi
}

main() {
    local scan_type="" target=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --severity)     SEVERITY_THRESHOLD="$2"; shift 2;;
            --max-critical) MAX_CRITICAL="$2";       shift 2;;
            --max-high)     MAX_HIGH="$2";            shift 2;;
            --max-medium)   MAX_MEDIUM="$2";          shift 2;;
            --no-fail)      FAIL_ON_THRESHOLD=false;  shift;;
            -h|--help)      usage;;
            scan)
                shift
                [[ $# -lt 2 ]] && { log_error "'scan' requires <type> <target>"; usage; }
                scan_type="$1"; target="$2"; shift 2;;
            *) log_error "Unknown option: $1"; usage;;
        esac
    done

    [[ -z "$scan_type" || -z "$target" ]] && { log_error "Missing scan type or target"; usage; }

    check_dependencies

    log_info "Severity threshold: $SEVERITY_THRESHOLD"
    log_info "Max critical: $MAX_CRITICAL | Max high: $MAX_HIGH | Max medium: $MAX_MEDIUM"
    echo

    local results_file
    results_file=$(run_scan "$scan_type" "$target")

    local counts
    counts=$(count_findings "$results_file" "$scan_type")
    rm -f "$results_file"

    IFS='|' read -r total critical high medium low <<< "$counts"

    enforce_policy "$total" "$critical" "$high" "$medium" "$low" "$target"
}

main "$@"
