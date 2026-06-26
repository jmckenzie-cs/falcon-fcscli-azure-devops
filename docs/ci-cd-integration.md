# CI/CD Integration Guide — Azure DevOps

This guide covers Azure DevOps-specific integration patterns for FCSCLI, including secret management, exit code handling, artifact best practices, and performance optimization.

---

## Azure DevOps Variable Groups (Secret Management)

All pipeline YAMLs in this repository reference a variable group named `falcon-credentials`. This is the recommended approach — credentials never appear in YAML files or git history.

### Setup

```yaml
# Create Variable Group: Pipelines → Library → Variable Groups
# Mark variables as secret, link group to pipeline
variables:
  - group: falcon-credentials
```

**Steps:**
1. **Pipelines → Library → + Variable group**
2. Name: `falcon-credentials`
3. Add variables (mark both as secret):
   - `FALCON_CLIENT_ID`
   - `FALCON_CLIENT_SECRET`
4. **Pipeline permissions tab** → authorize the pipelines that need access

### Passing Secrets to Bash Steps

Azure DevOps does not automatically expose variable group secrets as environment variables in bash steps. You must map them explicitly:

```yaml
- bash: bash scripts/download-fcscli.sh
  displayName: 'Download FCSCLI'
  env:
    FALCON_CLIENT_ID: $(FALCON_CLIENT_ID)        # maps secret to env var
    FALCON_CLIENT_SECRET: $(FALCON_CLIENT_SECRET) # maps secret to env var
```

---

## Exit Code Handling

FCSCLI uses distinct exit codes for scan results vs. configuration problems. Do **not** use a simple `|| exit 1` after an FCSCLI command — this collapses authentication errors into the same failure mode as scan findings.

### Exit Code Reference

| Code | Meaning | Recommended Action |
|---|---|---|
| 0 | Clean — no findings at threshold | Continue pipeline |
| 1 | Findings at or above threshold | Block — review artifact |
| 2 | General error (network, parse) | Fail pipeline |
| 201 | Authentication failed | Fail — verify credentials and region |
| 202 | Insufficient API permissions | Fail — check API client scopes |
| 203 | Rate limit exceeded | Retry with backoff |
| 204 | Resource not found | Fail — check FCSCLI version |
| 207 | Unsupported platform | Fail — check runner OS/architecture |

### Recommended Gate Pattern

The pipeline YAMLs in this repo use a two-step pattern:

1. Run the scan with `continueOnError: true` and capture the exit code into a pipeline variable
2. Publish artifacts (so they're available even on failure)
3. Re-raise the exit code in a separate gate step with descriptive error messages

```yaml
# Step 1: Run scan, capture exit code
- bash: |
    ./fcs scan iac --path iac/ --fail-on "critical=1,high=1" ...
    IAC_EXIT=$?
    echo "##vso[task.setvariable variable=IacScanExit]$IAC_EXIT"
    exit $IAC_EXIT
  displayName: 'Run IaC Scan'
  continueOnError: true
  env:
    FALCON_CLIENT_ID: $(FALCON_CLIENT_ID)
    FALCON_CLIENT_SECRET: $(FALCON_CLIENT_SECRET)

# Step 2: Publish artifacts
- task: PublishPipelineArtifact@1
  condition: always()    # critical: publish even on failure
  ...

# Step 3: Gate with descriptive messages
- bash: |
    EXIT=$(IacScanExit)
    case "$EXIT" in
      0)   echo "Scan passed." ;;
      1)   echo "##vso[task.logissue type=error]Scan found critical/high issues."
           exit 1 ;;
      201) echo "##vso[task.logissue type=error]Auth failed (exit 201)."
           exit 1 ;;
      202) echo "##vso[task.logissue type=error]Insufficient permissions (exit 202)."
           exit 1 ;;
      *)   echo "##vso[task.logissue type=error]FCSCLI exited with code $EXIT."
           exit 1 ;;
    esac
  displayName: 'Enforce Gate'
```

---

## Recommended Shift-Left Policy

| Finding Type | Default Threshold | Action |
|---|---|---|
| IaC Critical | Any | Block merge |
| IaC High | Any | Block merge |
| IaC Medium | — | Warn only (non-blocking) |
| IaC Low | — | Log only |
| Image ExPRT Critical | Any | Block deploy |
| Image ExPRT High | Any | Block deploy |
| Image ExPRT Medium | — | Warn only |
| Secrets in IaC | Any | Block immediately |

**Key principle**: Use `--minimum-exprt high` (not `--minimum-severity critical`) for image scanning. ExPRT is CrowdStrike's AI-powered exploitability triage score and produces significantly fewer false positives.

---

## Pipeline Artifact Best Practices

Always publish scan artifacts even when a scan fails. Without `condition: always()`, a failing scan step prevents the artifact upload — leaving you with no results to review.

```yaml
- task: PublishPipelineArtifact@1
  displayName: 'Publish Scan Results'
  condition: always()    # critical: upload even when scan step fails
  inputs:
    targetPath: '$(System.DefaultWorkingDirectory)/scan-output'
    artifact: 'scan-results'
    publishLocation: 'pipeline'
```

### Recommended Artifact Layout

```
iac-scan-results/          (artifact name)
├── iac-scan-output.json
└── iac-scan-output.sarif

image-scan-results/        (artifact name)
├── image-scan-results.json
└── image-scan-results.sarif
```

Publish JSON for report generation and SARIF for security dashboard integration.

---

## Performance Optimization

### Cache the FCSCLI Binary

Avoid downloading the binary on every pipeline run by caching it between runs:

```yaml
- task: Cache@2
  displayName: 'Cache FCSCLI Binary'
  inputs:
    key: 'fcs | "$(Agent.OS)" | v1'
    path: '$(Pipeline.Workspace)/fcs-cache'
    cacheHitVar: FCS_CACHE_HIT

- bash: |
    if [ "$(FCS_CACHE_HIT)" != "true" ]; then
      bash scripts/download-fcscli.sh
      mkdir -p $(Pipeline.Workspace)/fcs-cache
      cp ./fcs $(Pipeline.Workspace)/fcs-cache/fcs
    else
      cp $(Pipeline.Workspace)/fcs-cache/fcs ./fcs
    fi
    chmod +x ./fcs
  displayName: 'Install FCSCLI'
  env:
    FALCON_CLIENT_ID: $(FALCON_CLIENT_ID)
    FALCON_CLIENT_SECRET: $(FALCON_CLIENT_SECRET)
```

### Parallel IaC Scanning

Scan multiple IaC directories in parallel using a matrix strategy:

```yaml
jobs:
  - job: IaCScan
    strategy:
      matrix:
        terraform:
          IAC_PATH: 'iac/terraform/'
        kubernetes:
          IAC_PATH: 'iac/kubernetes/'
        cloudformation:
          IAC_PATH: 'iac/cloudformation/'
    steps:
      - bash: |
          ./fcs scan iac \
            --path $(IAC_PATH) \
            --report-formats json,sarif \
            --output-path scan-output/ \
            --fail-on "critical=1,high=1"
        displayName: 'Scan $(IAC_PATH)'
        env:
          FALCON_CLIENT_ID: $(FALCON_CLIENT_ID)
          FALCON_CLIENT_SECRET: $(FALCON_CLIENT_SECRET)
```

### Path-Based Triggers

Avoid running expensive scans on unrelated changes:

```yaml
trigger:
  paths:
    include:
      - iac/**          # only trigger IaC scan on IaC changes
      - containers/**   # only trigger image scan on container changes
      - Dockerfile
```

---

## Generating HTML Reports

Use `scripts/generate-report.sh` to convert JSON scan output to a human-readable HTML report:

```yaml
- bash: |
    ./scripts/generate-report.sh image-scan-results.json \
      --title "Image Scan - $(Build.BuildNumber)" \
      > image-scan-report.html
  displayName: 'Generate HTML Report'
  condition: always()

- task: PublishPipelineArtifact@1
  displayName: 'Publish HTML Report'
  condition: always()
  inputs:
    targetPath: '$(System.DefaultWorkingDirectory)/image-scan-report.html'
    artifact: 'image-scan-report'
```

---

## Policy Enforcement with `enforce-policy.sh`

For more granular threshold control than `--fail-on` provides, use the included script:

```yaml
- bash: |
    ./scripts/enforce-policy.sh scan image $(IMAGE_TAG) \
      --max-critical 0 \
      --max-high 0 \
      --max-medium 10
  displayName: 'Enforce Image Policy'
  env:
    FALCON_CLIENT_ID: $(FALCON_CLIENT_ID)
    FALCON_CLIENT_SECRET: $(FALCON_CLIENT_SECRET)
```

See `scripts/enforce-policy.sh --help` for all options.
