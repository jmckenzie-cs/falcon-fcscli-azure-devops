#!/usr/bin/env bash
#
# generate-report.sh — Convert FCSCLI JSON scan results to an HTML report
#
# PURPOSE
#   Reads a JSON file produced by 'fcs scan image' or 'fcs scan iac'
#   and writes a styled HTML report to stdout. Redirect to a file to save.
#
# USAGE
#   ./scripts/generate-report.sh <scan-results.json> [OPTIONS] > report.html
#
# OPTIONS
#   --title TITLE       Custom report title (default: FCS Security Scan Report)
#   --no-details        Omit per-finding detail section (summary counts only)
#   -h, --help          Show this help
#
# ENVIRONMENT VARIABLES
#   REPORT_TITLE        Report title (overridden by --title flag)
#   INCLUDE_DETAILS     true | false  (default: true)
#
# EXAMPLES
#   # Generate full HTML report
#   ./scripts/generate-report.sh scan-results.json > report.html
#
#   # Custom title
#   ./scripts/generate-report.sh scan-results.json --title "Production Scan $(date +%F)" > report.html
#
#   # Summary only
#   ./scripts/generate-report.sh scan-results.json --no-details > summary.html
#
# REQUIREMENTS
#   jq  — used for JSON parsing (brew install jq  /  apt-get install jq)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_TITLE="${REPORT_TITLE:-FCS Security Scan Report}"
INCLUDE_DETAILS="${INCLUDE_DETAILS:-true}"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

usage() {
    sed -n '/^# USAGE/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# *//'
    exit 1
}

check_jq() {
    if ! command -v jq &> /dev/null; then
        log_error "'jq' not found. Install: brew install jq  (macOS) or  apt-get install jq  (Linux)"
        exit 1
    fi
}

detect_scan_type() {
    local file="$1"
    if jq -e '.vulnerabilities' "$file" &>/dev/null; then
        echo "image"
    elif jq -e '.issues' "$file" &>/dev/null; then
        echo "iac"
    else
        log_error "Cannot detect scan type. Expected .vulnerabilities or .issues in JSON."
        exit 1
    fi
}

get_counts() {
    local file="$1" scan_type="$2"
    local field
    [[ "$scan_type" == "image" ]] && field="vulnerabilities" || field="issues"

    local total critical high medium low
    total=$(jq    ".$field | length" "$file")
    critical=$(jq "[.$field[] | select(.severity==\"CRITICAL\" or .severity==\"Critical\")] | length" "$file")
    high=$(jq     "[.$field[] | select(.severity==\"HIGH\"     or .severity==\"High\")]     | length" "$file")
    medium=$(jq   "[.$field[] | select(.severity==\"MEDIUM\"   or .severity==\"Medium\")]   | length" "$file")
    low=$(jq      "[.$field[] | select(.severity==\"LOW\"      or .severity==\"Low\")]      | length" "$file")

    echo "$total|$critical|$high|$medium|$low"
}

get_target() {
    local file="$1" scan_type="$2"
    if [[ "$scan_type" == "image" ]]; then
        jq -r '.image // "Unknown Image"' "$file"
    else
        jq -r '.path  // "Unknown Path"'  "$file"
    fi
}

html_header() {
    cat << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FCS Security Scan Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
               line-height: 1.6; color: #333; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white;
                     padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; margin-bottom: 10px; font-size: 2em; }
        .header { border-bottom: 3px solid #e74c3c; padding-bottom: 20px; margin-bottom: 30px; }
        .metadata { color: #7f8c8d; font-size: 0.9em; margin-top: 10px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
                   gap: 20px; margin-bottom: 30px; }
        .card { background: #f8f9fa; padding: 20px; border-radius: 6px; border-left: 4px solid #3498db; }
        .card.critical { border-left-color: #e74c3c; background: #fff0f0; }
        .card.high     { border-left-color: #e67e22; background: #fff5ee; }
        .card.medium   { border-left-color: #f39c12; background: #fffaee; }
        .card.low      { border-left-color: #95a5a6; background: #f8f9fa; }
        .card h3 { font-size: 0.85em; color: #7f8c8d; text-transform: uppercase; margin-bottom: 8px; }
        .card .count { font-size: 2.5em; font-weight: bold; color: #2c3e50; }
        .details { margin-top: 30px; }
        .details h2 { color: #2c3e50; margin-bottom: 20px; padding-bottom: 10px;
                      border-bottom: 2px solid #ecf0f1; }
        .finding { background: #f8f9fa; padding: 15px; margin-bottom: 12px;
                   border-radius: 6px; border-left: 4px solid #3498db; }
        .finding.critical { border-left-color: #e74c3c; }
        .finding.high     { border-left-color: #e67e22; }
        .finding.medium   { border-left-color: #f39c12; }
        .finding.low      { border-left-color: #95a5a6; }
        .finding h4 { color: #2c3e50; margin-bottom: 6px; }
        .finding .meta { display: flex; gap: 15px; font-size: 0.85em; color: #7f8c8d; margin-bottom: 8px; }
        .badge { display: inline-block; padding: 2px 7px; border-radius: 3px;
                 font-size: 0.75em; font-weight: bold; text-transform: uppercase; }
        .badge.critical { background: #e74c3c; color: white; }
        .badge.high     { background: #e67e22; color: white; }
        .badge.medium   { background: #f39c12; color: white; }
        .badge.low      { background: #95a5a6; color: white; }
        .description { color: #555; margin-top: 8px; line-height: 1.5; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ecf0f1;
                  text-align: center; color: #95a5a6; font-size: 0.85em; }
        @media print { body { background: white; } .container { box-shadow: none; } }
    </style>
</head>
<body>
    <div class="container">
EOF
}

html_summary() {
    local target="$1" scan_type="$2" total="$3" critical="$4" high="$5" medium="$6" low="$7"
    cat << EOF
        <div class="header">
            <h1>$REPORT_TITLE</h1>
            <div class="metadata">
                <strong>Target:</strong> $target<br>
                <strong>Scan Type:</strong> $(echo "$scan_type" | tr '[:lower:]' '[:upper:]')<br>
                <strong>Generated:</strong> $(date)
            </div>
        </div>
        <div class="summary">
            <div class="card"><h3>Total</h3><div class="count">$total</div></div>
            <div class="card critical"><h3>Critical</h3><div class="count">$critical</div></div>
            <div class="card high"><h3>High</h3><div class="count">$high</div></div>
            <div class="card medium"><h3>Medium</h3><div class="count">$medium</div></div>
            <div class="card low"><h3>Low</h3><div class="count">$low</div></div>
        </div>
EOF
}

html_image_details() {
    local file="$1"
    cat << 'EOF'
        <div class="details"><h2>Vulnerability Details</h2>
EOF
    jq -r '.vulnerabilities[] |
        "<div class=\"finding " + (.severity | ascii_downcase) + "\">" +
        "<h4>" + (.cve // .name // "Unknown") + "</h4>" +
        "<div class=\"meta\">" +
        "<span class=\"badge " + (.severity | ascii_downcase) + "\">" + .severity + "</span>" +
        "<span><strong>Package:</strong> " + (.package // "N/A") + "</span>" +
        "<span><strong>Version:</strong> " + (.version // "N/A") + "</span>" +
        "</div><div class=\"description\">" + (.description // "No description available") + "</div></div>"
    ' "$file"
    echo "        </div>"
}

html_iac_details() {
    local file="$1"
    cat << 'EOF'
        <div class="details"><h2>Issue Details</h2>
EOF
    jq -r '.issues[] |
        "<div class=\"finding " + (.severity | ascii_downcase) + "\">" +
        "<h4>" + (.title // .id // "Unknown Issue") + "</h4>" +
        "<div class=\"meta\">" +
        "<span class=\"badge " + (.severity | ascii_downcase) + "\">" + .severity + "</span>" +
        "<span><strong>File:</strong> " + (.file // "N/A") + "</span>" +
        "<span><strong>Line:</strong> " + ((.line // "N/A") | tostring) + "</span>" +
        "</div><div class=\"description\">" + (.description // "No description available") + "</div></div>"
    ' "$file"
    echo "        </div>"
}

html_footer() {
    cat << 'EOF'
        <div class="footer">
            <p>Generated by CrowdStrike Falcon Cloud Security CLI</p>
        </div>
    </div>
</body>
</html>
EOF
}

main() {
    local json_file=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --title)      REPORT_TITLE="$2";   shift 2;;
            --no-details) INCLUDE_DETAILS=false; shift;;
            -h|--help)    usage;;
            *)
                if [[ -z "$json_file" ]]; then
                    json_file="$1"; shift
                else
                    log_error "Unknown option: $1"; usage
                fi
                ;;
        esac
    done

    [[ -z "$json_file" ]] && { log_error "No JSON file specified"; usage; }
    [[ ! -f "$json_file" ]] && { log_error "File not found: $json_file"; exit 1; }

    check_jq

    log_info "Generating HTML report from: $json_file"

    local scan_type
    scan_type=$(detect_scan_type "$json_file")
    log_info "Detected scan type: $scan_type"

    local counts
    counts=$(get_counts "$json_file" "$scan_type")
    IFS='|' read -r total critical high medium low <<< "$counts"

    local target
    target=$(get_target "$json_file" "$scan_type")

    html_header
    html_summary "$target" "$scan_type" "$total" "$critical" "$high" "$medium" "$low"

    if [[ "$INCLUDE_DETAILS" == "true" ]]; then
        if [[ "$scan_type" == "image" ]]; then
            html_image_details "$json_file"
        else
            html_iac_details "$json_file"
        fi
    fi

    html_footer

    log_success "Report generated" >&2
}

main "$@"
