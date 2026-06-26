#!/usr/bin/env bash

# FCS CLI Infrastructure as Code (IaC) Scanning Examples
# Comprehensive examples of IaC scanning capabilities

set -euo pipefail

echo "=========================================="
echo "FCS CLI - IaC Scanning Examples"
echo "=========================================="
echo

# Example 1: Basic IaC Scanning
echo "Example 1: Basic IaC Scanning"
echo "------------------------------"
cat << 'EOF'
# Scan Terraform files in current directory
fcs scan iac .

# Scan specific directory
fcs scan iac ./terraform/

# Scan Kubernetes manifests
fcs scan iac ./k8s/

# Scan CloudFormation templates
fcs scan iac ./cloudformation/

# Scan Helm charts
fcs scan iac ./charts/
EOF
echo

# Example 2: Output Formats
echo "Example 2: Output Formats"
echo "-------------------------"
cat << 'EOF'
# JSON output
fcs scan iac ./terraform/ --output json

# Save to file
fcs scan iac ./terraform/ --output json > iac-results.json

# SARIF format (for GitHub Advanced Security, Azure DevOps, etc.)
fcs scan iac ./terraform/ --output sarif > iac-results.sarif

# Pretty-print with jq
fcs scan iac ./terraform/ --output json | jq '.'
EOF
echo

# Example 3: Scanning Multiple IaC Types
echo "Example 3: Scanning Multiple IaC Types"
echo "---------------------------------------"
cat << 'EOF'
# Scan entire infrastructure directory (mixed IaC types)
fcs scan iac ./infrastructure/

# Directory structure:
# infrastructure/
# ├── terraform/
# │   ├── main.tf
# │   ├── variables.tf
# │   └── outputs.tf
# ├── kubernetes/
# │   ├── deployment.yaml
# │   ├── service.yaml
# │   └── ingress.yaml
# └── cloudformation/
#     └── stack.yaml
EOF
echo

# Example 4: Verbose Mode
echo "Example 4: Verbose Mode"
echo "-----------------------"
cat << 'EOF'
# Enable verbose output
fcs --verbose scan iac ./terraform/

# Set via environment variable
export FCS_VERBOSE=true
fcs scan iac ./terraform/
EOF
echo

# Example 5: Using Different Profiles
echo "Example 5: Using Different Profiles"
echo "------------------------------------"
cat << 'EOF'
# Scan with specific profile
fcs --profile production scan iac ./terraform/

# Scan development environment
fcs --profile development scan iac ./terraform/dev/
EOF
echo

# Example 6: CI/CD Integration (Azure DevOps)
echo "Example 6: CI/CD Integration (Azure DevOps)"
echo "--------------------------------------------"
cat << 'EOF'
# In azure-pipelines.yml
- bash: |
    mkdir -p iac-scan-output
    ./fcs scan iac \
      --path iac/ \
      --report-formats json,sarif \
      --output-path iac-scan-output/ \
      --upload \
      --fail-on "critical=1,high=1"
    IAC_EXIT=$?
    echo "##vso[task.setvariable variable=IacScanExit]$IAC_EXIT"
    exit $IAC_EXIT
  displayName: 'Run IaC Scan'
  continueOnError: true
  env:
    FALCON_CLIENT_ID: $(FALCON_CLIENT_ID)
    FALCON_CLIENT_SECRET: $(FALCON_CLIENT_SECRET)
EOF
echo

# Example 7: Parsing IaC Results with jq
echo "Example 7: Parsing IaC Results with jq"
echo "---------------------------------------"
cat << 'EOF'
# Count total misconfigurations
fcs scan iac ./terraform/ --output json | jq '.issues | length'

# Filter by severity
fcs scan iac ./terraform/ --output json | jq '.issues[] | select(.severity == "HIGH")'

# Group by file
fcs scan iac ./terraform/ --output json | jq '.issues | group_by(.file) | map({file: .[0].file, count: length})'

# List unique rule IDs
fcs scan iac ./terraform/ --output json | jq -r '.issues[].rule_id' | sort -u

# Extract high and critical issues
fcs scan iac ./terraform/ --output json | jq '.issues[] | select(.severity == "HIGH" or .severity == "CRITICAL")'
EOF
echo

# Example 8: Terraform Specific Examples
echo "Example 8: Terraform Specific Examples"
echo "---------------------------------------"
cat << 'EOF'
# Scan Terraform root module
fcs scan iac ./terraform/

# Scan Terraform modules directory
fcs scan iac ./terraform/modules/

# Example Terraform file (main.tf)
cat << 'TERRAFORM'
resource "aws_s3_bucket" "example" {
  bucket = "my-bucket"

  # This will be flagged: no encryption enabled
  # Fix: Add server_side_encryption_configuration block
}

resource "aws_security_group" "example" {
  name        = "example"
  description = "Example security group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # This will be flagged: too permissive
  }
}
TERRAFORM

fcs scan iac ./terraform/ --output json | jq '.issues[] | select(.file | contains("main.tf"))'
EOF
echo

# Example 9: Kubernetes Manifest Examples
echo "Example 9: Kubernetes Manifest Examples"
echo "----------------------------------------"
cat << 'EOF'
# Scan Kubernetes manifests
fcs scan iac ./k8s/

# Example deployment that will generate findings (deployment.yaml)
cat << 'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        securityContext:
          privileged: true  # This will be flagged: privileged container
        resources:
          limits:
            memory: "128Mi"
            cpu: "500m"
YAML

fcs scan iac ./k8s/ --output json | jq '.issues[] | select(.rule_id | contains("privileged"))'
EOF
echo

# Example 10: CloudFormation Examples
echo "Example 10: CloudFormation Examples"
echo "------------------------------------"
cat << 'EOF'
# Scan CloudFormation templates
fcs scan iac ./cloudformation/

# Example template (stack.yaml)
cat << 'YAML'
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: my-bucket
      # Missing: BucketEncryption — will be flagged

  MySecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Example security group
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 22
          ToPort: 22
          CidrIp: 0.0.0.0/0  # Will be flagged: too permissive
YAML

fcs scan iac ./cloudformation/ --output json
EOF
echo

# Example 11: Policy Enforcement
echo "Example 11: Policy Enforcement"
echo "-------------------------------"
cat << 'EOF'
# Use the included enforce-policy.sh script
./scripts/enforce-policy.sh scan iac ./terraform/ --max-critical 0 --max-high 0

# Or inline in a CI/CD script
fcs scan iac ./terraform/ --output json > iac-results.json

CRITICAL=$(jq -r '[.issues[] | select(.severity=="CRITICAL")] | length' iac-results.json)
HIGH=$(jq -r '[.issues[] | select(.severity=="HIGH")] | length' iac-results.json)

echo "Critical issues: $CRITICAL"
echo "High issues: $HIGH"

if [[ $CRITICAL -gt 0 ]] || [[ $HIGH -gt 0 ]]; then
  echo "ERROR: Policy violation — critical or high IaC issues found!"
  exit 1
fi

echo "Policy check passed!"
EOF
echo

# Example 12: Pre-commit Hook
echo "Example 12: Pre-commit Hook"
echo "----------------------------"
cat << 'EOF'
#!/bin/bash
# .git/hooks/pre-commit

echo "Running IaC security scan on staged files..."

CHANGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(tf|yaml|yml|json)$')

if [[ -z "$CHANGED_FILES" ]]; then
  echo "No IaC files staged"
  exit 0
fi

TMP_DIR=$(mktemp -d)
echo "$CHANGED_FILES" | while read -r file; do
  mkdir -p "$TMP_DIR/$(dirname "$file")"
  cp "$file" "$TMP_DIR/$file"
done

if fcs scan iac "$TMP_DIR" --output json > /tmp/iac-scan.json; then
  ISSUES=$(jq -r '.issues | length' /tmp/iac-scan.json)
  if [[ $ISSUES -gt 0 ]]; then
    echo "WARNING: Found $ISSUES IaC security issues"
    jq -r '.issues[] | "\(.severity): \(.title) in \(.file)"' /tmp/iac-scan.json
    read -r -p "Commit anyway? [y/N] " -n 1
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && { rm -rf "$TMP_DIR"; exit 1; }
  fi
fi

rm -rf "$TMP_DIR"
exit 0
EOF
echo

echo "=========================================="
echo "For more information:"
echo "  fcs scan iac --help"
echo "  fcs --help"
echo "=========================================="
