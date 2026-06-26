# Falcon Cloud Security CLI — Azure DevOps CI/CD Examples

This repository provides ready-to-use Azure DevOps pipeline templates and helper scripts for integrating the CrowdStrike Falcon Cloud Security CLI (FCSCLI) into your CI/CD workflows. Use it to scan container images and Infrastructure as Code (IaC) templates automatically on every pull request and merge.

---

## What's in This Repo

```
├── azure-pipelines/
│   ├── combined-pipeline.yml      # Full IaC + image scan pipeline
│   ├── image-scan-pipeline.yml    # Container image scan only
│   └── iac-scan-pipeline.yml      # IaC scan only
├── scripts/
│   ├── install-fcscli.sh          # Install FCSCLI from a local download
│   ├── download-fcscli.sh         # Download FCSCLI via CrowdStrike API
│   ├── enforce-policy.sh          # Fail builds based on severity thresholds
│   └── generate-report.sh         # Convert JSON scan results to HTML report
├── examples/
│   ├── image-scan-examples.sh     # Image scanning patterns and jq parsing
│   └── iac-scan-examples.sh       # IaC scanning patterns and policy examples
└── docs/
    ├── quickstart.md              # 5-minute setup guide
    ├── configuration.md           # Environment variables and options reference
    └── ci-cd-integration.md       # Pipeline integration guide
```

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| CrowdStrike Subscription | Active Falcon Cloud Security license |
| API Credentials | OAuth2 Client ID + Secret (see [docs/quickstart.md](docs/quickstart.md)) |
| API Scopes | `Falcon Container CLI: Read/Write`, `Falcon Container Image: Read/Write`, `Infrastructure as Code: Read/Write` |
| Azure DevOps | A project with Pipelines enabled |
| Azure DevOps Variable Group | Named `falcon-credentials` containing `FALCON_CLIENT_ID` and `FALCON_CLIENT_SECRET` (see below) |
| Build Agent | Ubuntu-based agent with Docker installed (for image scanning) |

---

## 5-Minute Quickstart

### Step 1 — Create an Azure DevOps Variable Group

1. In Azure DevOps, go to **Pipelines → Library → + Variable group**
2. Name it exactly: `falcon-credentials`
3. Add two variables and mark each as **secret**:
   - `FALCON_CLIENT_ID` — your CrowdStrike OAuth2 Client ID
   - `FALCON_CLIENT_SECRET` — your CrowdStrike OAuth2 Client Secret
4. Click **Save**
5. On the **Pipeline permissions** tab, authorize the pipelines that will use this group

### Step 2 — Clone This Repo

```bash
git clone <this-repo-url>
cd falcon-fcscli-azure-devops
```

### Step 3 — Add a Pipeline to Your Project

Copy the pipeline YAML that fits your use case into your application repository:

```bash
# Full scan (IaC + images) — recommended starting point
cp azure-pipelines/combined-pipeline.yml <your-app-repo>/azure-pipelines.yml

# Or pick a focused pipeline
cp azure-pipelines/image-scan-pipeline.yml <your-app-repo>/azure-pipelines.yml
cp azure-pipelines/iac-scan-pipeline.yml   <your-app-repo>/azure-pipelines.yml
```

Then update the pipeline variables to match your image name and IaC paths.

### Step 4 — Create the Pipeline in Azure DevOps

1. In Azure DevOps, go to **Pipelines → New pipeline**
2. Choose your repository source (Azure Repos, GitHub, etc.) and select the repo
3. When asked to configure, choose **Existing Azure Pipelines YAML file**
4. Select the branch and path to the YAML you placed in your repo (e.g. `/azure-pipelines.yml`)
5. Click **▾ → Save** (save without running first)
6. On the first run, Azure DevOps will prompt you to authorize access to the `falcon-credentials` variable group — click **Permit**
7. Click **Run pipeline**

For a screen-by-screen walkthrough including the variable group authorization prompt, see **[docs/quickstart.md](docs/quickstart.md)**.

---

## Key Design Decisions

**No secrets in YAML** — All credentials are referenced from the `falcon-credentials` variable group. Never hardcode credentials in pipeline files.

**Exit code handling** — FCSCLI uses distinct exit codes for scan findings vs. configuration errors. The pipelines capture `$?` and use a gate step to distinguish scan failures (exit 1) from auth errors (exit 201+). See [docs/ci-cd-integration.md](docs/ci-cd-integration.md#exit-code-reference) for the full table.

**Artifacts always published** — Scan result artifacts are published even when a scan fails, so you can review findings without re-running the pipeline.

**ExPRT severity for images** — Image scan pipelines use `--minimum-exprt high` rather than `--minimum-severity`. ExPRT is CrowdStrike's AI-powered exploitability triage score and produces fewer false positives.

---

## Recommended Policy Thresholds

| Finding Type | Default Threshold | Action |
|---|---|---|
| IaC Critical | Any | Block merge |
| IaC High | Any | Block merge |
| IaC Medium | — | Warn only |
| Image ExPRT Critical | Any | Block deploy |
| Image ExPRT High | Any | Block deploy |
| Secrets in IaC | Any | Block immediately |

Adjust `--fail-on` (IaC) and `--minimum-exprt` (images) in the pipeline YAMLs to match your organization's policy.

---

## Further Reading

- [docs/quickstart.md](docs/quickstart.md) — Credentials setup, first scan, common errors
- [docs/configuration.md](docs/configuration.md) — All environment variables and CLI flags
- [docs/ci-cd-integration.md](docs/ci-cd-integration.md) — Exit code reference, artifact best practices, performance tips

---

## Support

For issues with the FCSCLI itself, open a case at the [CrowdStrike Support Portal](https://supportportal.crowdstrike.com).

For questions about these pipeline examples, contact your CrowdStrike account team or sales engineer.
