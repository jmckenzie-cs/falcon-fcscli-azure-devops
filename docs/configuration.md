# FCSCLI Configuration Reference

This document covers all environment variables and key CLI flags used by FCSCLI and the helper scripts in this repository.

---

## Authentication

### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `FALCON_CLIENT_ID` | Yes | CrowdStrike OAuth2 Client ID |
| `FALCON_CLIENT_SECRET` | Yes | CrowdStrike OAuth2 Client Secret |
| `FALCON_CLOUD` | No | Falcon region: `us-1`, `us-2`, `eu-1`, `us-gov-1`, `us-gov-2` (default: `us-1`). Used by `fcs configure` and interactive CLI. **Not read by `download-fcscli.sh`** — use `FALCON_API_URL` for that script. |
| `FALCON_API_URL` | No | Full API base URL — takes precedence over `FALCON_CLOUD`. Required for `download-fcscli.sh` in non-`us-1` regions. Example: `https://api.eu-1.crowdstrike.com` |

### Region Reference

| Tenant URL | `FALCON_CLOUD` value | `FALCON_API_URL` |
|---|---|---|
| https://falcon.crowdstrike.com | `us-1` | `https://api.crowdstrike.com` |
| https://falcon.us-2.crowdstrike.com | `us-2` | `https://api.us-2.crowdstrike.com` |
| https://falcon.eu-1.crowdstrike.com | `eu-1` | `https://api.eu-1.crowdstrike.com` |
| https://falcon.laggar.gcw.crowdstrike.com | `us-gov-1` | `https://api.laggar.gcw.crowdstrike.com` |

### Interactive Configuration

```bash
# Guided interactive setup
fcs configure

# Non-interactive
fcs configure \
  --client-id "$FALCON_CLIENT_ID" \
  --client-secret "$FALCON_CLIENT_SECRET" \
  --falcon-cloud us-1

# Create a named profile
fcs configure --profile production

# List configured profiles
fcs configure list
```

---

## Global CLI Flags

These flags apply to all `fcs` commands:

| Flag | Env Variable | Description |
|---|---|---|
| `--verbose` | `FCS_VERBOSE=true` | Enable verbose logging output |
| `--timeout N` | `FCS_TIMEOUT=N` | Command timeout in seconds (default: 300) |
| `--profile NAME` | `FCS_PROFILE=NAME` | Use a named configuration profile |

---

## Image Scan Options

```bash
fcs scan image [FLAGS] <image>
```

| Flag | Description |
|---|---|
| `--format json\|sarif` | Output format (default: human-readable) |
| `--output <file>` | Write results to file instead of stdout |
| `--upload` | Upload results to the Falcon Console |
| `--minimum-exprt <level>` | Minimum ExPRT severity to report: `critical`, `high`, `medium`, `low` |
| `--minimum-severity <level>` | Minimum CVE severity to report (use `--minimum-exprt` instead for AI-powered triage) |
| `--timeout N` | Override global timeout for this scan |

### ExPRT vs Severity

**Use `--minimum-exprt high` rather than `--minimum-severity critical`** for image scanning. ExPRT (Exploit Prediction Rating Technology) is CrowdStrike's AI-powered exploitability score. It filters out theoretical vulnerabilities that are not practically exploitable, reducing noise and false positives compared to raw CVE severity.

```bash
# Recommended — ExPRT-based gate
fcs scan image myapp:latest --minimum-exprt high

# Not recommended — CVE severity produces more noise
fcs scan image myapp:latest --minimum-severity critical
```

---

## IaC Scan Options

```bash
fcs scan iac [FLAGS]
```

| Flag | Description |
|---|---|
| `--path <dir>` | Directory to scan (default: current directory) |
| `--report-formats json,sarif` | Comma-separated list of output formats |
| `--output-path <dir>` | Directory to write report files |
| `--upload` | Upload results to the Falcon Console |
| `--fail-on <expression>` | Exit 1 when findings meet the expression, e.g. `"critical=1,high=1"` |

### `--fail-on` Expression Syntax

```
--fail-on "critical=1,high=1"    # fail if any critical OR any high finding
--fail-on "critical=1"            # fail only on critical
--fail-on "high=5"                # fail if more than 5 high findings
```

---

## Script Environment Variables

### `download-fcscli.sh`

| Variable | Default | Description |
|---|---|---|
| `FALCON_CLIENT_ID` | — | Required |
| `FALCON_CLIENT_SECRET` | — | Required |
| `FALCON_API_URL` | `https://api.crowdstrike.com` | API base URL |
| `FCS_TARGET_OS` | auto-detect | Override OS: `linux`, `darwin` |
| `FCS_TARGET_ARCH` | auto-detect | Override arch: `amd64`, `arm64` |
| `OUTPUT_DIR` | `.` | Directory for downloaded archive |

### `enforce-policy.sh`

| Variable | Default | Description |
|---|---|---|
| `SEVERITY_THRESHOLD` | `high` | Minimum severity level to evaluate |
| `MAX_CRITICAL` | `0` | Maximum critical findings before failing |
| `MAX_HIGH` | `5` | Maximum high findings before failing |
| `MAX_MEDIUM` | `20` | Maximum medium findings before failing |
| `FAIL_ON_THRESHOLD` | `true` | Set `false` to warn without failing |

### `generate-report.sh`

| Variable | Default | Description |
|---|---|---|
| `REPORT_TITLE` | `FCS Security Scan Report` | Report page title |
| `INCLUDE_DETAILS` | `true` | Set `false` for summary-only output |

---

## Exit Code Reference

| Code | Meaning | Recommended Response |
|---|---|---|
| 0 | Clean — no findings at threshold | Continue pipeline |
| 1 | Findings at or above threshold (image scan) | Block pipeline |
| 2 | General error (network, parse) | Fail pipeline |
| 40 | Policy violation — findings exceeded threshold (IaC scan) | Block pipeline |
| 201 | Authentication failed | Fail — verify credentials and region |
| 202 | Insufficient API permissions | Fail — check API client scopes |
| 203 | Rate limit exceeded | Retry with exponential backoff |
| 204 | Resource not found | Fail — check FCSCLI version |
| 207 | Unsupported platform | Fail — check runner OS/architecture |

> **Important**: Do not use `|| exit 1` to handle FCSCLI failures. Capture `$?` and use a `case` statement. Exit codes 201–207 indicate configuration issues, not scan findings. Treating them the same as exit code 1 hides the root cause.

See the pipeline YAMLs in `azure-pipelines/` for complete gate step examples.

---

## API Client Scopes

| Feature | Required Scopes |
|---|---|
| Image scanning | `Falcon Container CLI: Read/Write`<br>`Falcon Container Image: Read/Write` |
| IaC scanning | `Infrastructure as Code: Read/Write` |
| Programmatic CLI download | `Cloud Security Tools Download: Read` |

Applying the principle of least privilege: create separate API clients for different environments (dev, staging, prod) with only the scopes each environment needs.
