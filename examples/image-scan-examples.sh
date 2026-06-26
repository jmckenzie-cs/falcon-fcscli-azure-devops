#!/usr/bin/env bash

# FCS CLI Image Scanning Examples
# Comprehensive examples of image scanning capabilities

set -euo pipefail

echo "=========================================="
echo "FCS CLI - Image Scanning Examples"
echo "=========================================="
echo

# Example 1: Basic Image Scan
echo "Example 1: Basic Image Scan"
echo "----------------------------"
cat << 'EOF'
# Scan a public image from Docker Hub
fcs scan image nginx:latest

# Scan a specific version
fcs scan image nginx:1.21.0

# Scan using digest
fcs scan image nginx@sha256:abc123...
EOF
echo

# Example 2: Private Registry Scanning
echo "Example 2: Private Registry Scanning"
echo "-------------------------------------"
cat << 'EOF'
# Scan from private registry (requires Docker login first)
docker login myregistry.io
fcs scan image myregistry.io/myapp:v1.0.0

# Scan from AWS ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com
fcs scan image 123456789.dkr.ecr.us-east-1.amazonaws.com/myapp:latest

# Scan from Google Container Registry
gcloud auth configure-docker
fcs scan image gcr.io/my-project/myapp:v1.0.0

# Scan from Azure Container Registry
az acr login --name myregistry
fcs scan image myregistry.azurecr.io/myapp:latest
EOF
echo

# Example 3: Output Formats
echo "Example 3: Output Formats"
echo "-------------------------"
cat << 'EOF'
# JSON output (machine-readable)
fcs scan image nginx:latest --output json

# Save JSON to file
fcs scan image nginx:latest --output json > scan-results.json

# SARIF format (for security tools integration)
fcs scan image nginx:latest --output sarif > scan-results.sarif

# Pretty-print JSON with jq
fcs scan image nginx:latest --output json | jq '.'
EOF
echo

# Example 4: Verbose and Debug Mode
echo "Example 4: Verbose and Debug Mode"
echo "----------------------------------"
cat << 'EOF'
# Enable verbose output
fcs --verbose scan image nginx:latest

# Set via environment variable
export FCS_VERBOSE=true
fcs scan image nginx:latest
EOF
echo

# Example 5: Timeout Configuration
echo "Example 5: Timeout Configuration"
echo "---------------------------------"
cat << 'EOF'
# Increase timeout for large images (default: 300s)
fcs --timeout 600 scan image large-app:latest

# Set via environment variable
export FCS_TIMEOUT=900
fcs scan image large-app:latest
EOF
echo

# Example 6: Using Different Profiles
echo "Example 6: Using Different Profiles"
echo "------------------------------------"
cat << 'EOF'
# Scan with production profile
fcs --profile production scan image prod-app:latest

# Scan with development profile
fcs --profile development scan image dev-app:latest

# Create and use a new profile
fcs configure --profile testing
fcs --profile testing scan image test-app:latest
EOF
echo

# Example 7: Parsing Results with jq
echo "Example 7: Parsing Results with jq"
echo "-----------------------------------"
cat << 'EOF'
# Extract vulnerability count
fcs scan image nginx:latest --output json | jq '.vulnerabilities | length'

# Filter critical vulnerabilities
fcs scan image nginx:latest --output json | jq '.vulnerabilities[] | select(.severity == "CRITICAL")'

# Get unique CVE IDs
fcs scan image nginx:latest --output json | jq -r '.vulnerabilities[].cve_id' | sort -u

# Count vulnerabilities by severity
fcs scan image nginx:latest --output json | jq '.vulnerabilities | group_by(.severity) | map({severity: .[0].severity, count: length})'

# Extract package names with vulnerabilities
fcs scan image nginx:latest --output json | jq -r '.vulnerabilities[].package_name' | sort -u
EOF
echo

# Example 8: CI/CD Integration Patterns
echo "Example 8: CI/CD Integration Patterns"
echo "--------------------------------------"
cat << 'EOF'
# Scan newly built image in CI/CD
docker build -t myapp:${CI_COMMIT_SHA} .
fcs scan image myapp:${CI_COMMIT_SHA} --output json > scan-results.json

# Fail pipeline on critical vulnerabilities
fcs scan image myapp:latest --output json | jq -e '.vulnerabilities[] | select(.severity == "CRITICAL") | empty' || exit 1

# Generate HTML report from JSON
fcs scan image myapp:latest --output json > scan-results.json
./scripts/generate-report.sh scan-results.json > report.html
EOF
echo

# Example 9: Batch Scanning
echo "Example 9: Batch Scanning"
echo "-------------------------"
cat << 'EOF'
# Scan multiple images from a file (images.txt)
while IFS= read -r image; do
  echo "Scanning: $image"
  fcs scan image "$image" --output json > "${image//[:\/]/_}.json"
done < images.txt

# Scan all local Docker images
docker images --format "{{.Repository}}:{{.Tag}}" | while read -r image; do
  echo "Scanning: $image"
  fcs scan image "$image"
done
EOF
echo

# Example 10: Integration with Docker Build
echo "Example 10: Integration with Docker Build"
echo "------------------------------------------"
cat << 'EOF'
# Build and scan in one step
docker build -t myapp:latest . && fcs scan image myapp:latest

# Build, scan, and save results
docker build -t myapp:latest .
fcs scan image myapp:latest --output json > scan-results.json
fcs scan image myapp:latest --output sarif > scan-results.sarif
EOF
echo

# Example 11: Scanning with Custom Docker Socket
echo "Example 11: Scanning with Custom Docker Socket"
echo "-----------------------------------------------"
cat << 'EOF'
# Use custom Docker socket
export DOCKER_HOST=unix:///custom/docker.sock
fcs scan image nginx:latest

# Use Docker context
docker context use remote-docker
fcs scan image nginx:latest
EOF
echo

# Example 12: Automated Reporting
echo "Example 12: Automated Reporting"
echo "--------------------------------"
cat << 'EOF'
#!/bin/bash
# scan-and-report.sh

IMAGE="$1"
OUTPUT_DIR="./reports"
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${OUTPUT_DIR}/${IMAGE//[:\/]/_}-${TIMESTAMP}.json"

echo "Scanning: $IMAGE"
fcs scan image "$IMAGE" --output json > "$REPORT_FILE"

# Generate HTML report
./scripts/generate-report.sh "$REPORT_FILE" > "${REPORT_FILE%.json}.html"

# Summarize
CRITICAL=$(jq -r '[.vulnerabilities[] | select(.severity=="CRITICAL")] | length' "$REPORT_FILE")
HIGH=$(jq -r '[.vulnerabilities[] | select(.severity=="HIGH")] | length' "$REPORT_FILE")

echo "Scan complete — Critical: $CRITICAL  High: $HIGH"
echo "Report: $REPORT_FILE"

if [[ $CRITICAL -gt 0 ]]; then
  echo "ERROR: Critical vulnerabilities found!"
  exit 1
fi
EOF
echo

echo "=========================================="
echo "For more information:"
echo "  fcs scan image --help"
echo "  fcs --help"
echo "=========================================="
