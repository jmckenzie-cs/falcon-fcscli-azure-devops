# Quickstart — FCSCLI with Azure DevOps

Get your first security scan running in Azure DevOps pipelines in about 5 minutes.

---

## Prerequisites

- Active CrowdStrike Falcon Cloud Security subscription
- Access to the Falcon Console ([https://falcon.crowdstrike.com](https://falcon.crowdstrike.com))
- A Microsoft account (personal or work/school)
- Docker installed on your build agents (for image scanning)

---

## Step 0 — Get into Azure DevOps and enable Pipelines

> **Important:** Azure DevOps is a separate product from the Azure Portal. If you are at `portal.azure.com` you are in the wrong place. Azure DevOps lives at `dev.azure.com`.

### 0a — Sign in to Azure DevOps

1. Go to **[https://dev.azure.com](https://dev.azure.com)**
2. Sign in with your Microsoft account

### 0b — Create or select an Organization

An Organization is the top-level container. You may already have one from a previous sign-in.

- If you see an organization listed, click it to open it.
- If not, click **Create new organization**, accept the Terms of Service, give it a name (e.g., your company name), and click **Continue**.

### 0c — Create a Project

Inside your organization you need at least one Project.

1. Click **New project** (top right)
2. Give it a name (e.g., `my-app`)
3. Set visibility to **Private**
4. Click **Create**

### 0d — Enable Pipelines

By default, some Azure DevOps features may be turned off for new projects.

1. In your project, click **Project settings** (gear icon, bottom-left corner)
2. Under the **Boards** section in the left panel, look for **Services** — or scroll to find **Azure Pipelines**
3. If you see a toggle next to **Pipelines** that is **Off**, click it to turn it **On**
4. Click **Save**

After saving, go back to your project's main page. You should now see **Pipelines** (rocket icon) in the left sidebar.

> If you still do not see Pipelines, check that your account has the **Project Administrator** role: **Project settings → Permissions → Groups → Project Administrators** — your account must be listed there.

---

## Step 1 — Create API Credentials (2 minutes)

1. In the Falcon Console, go to **Support and resources → API clients and keys**
2. Click **Add new API client**
3. Name it something like `Azure DevOps CI`
4. Enable the following scopes:

   | Scope | Permission |
   |---|---|
   | Falcon Container CLI | Read + Write |
   | Falcon Container Image | Read + Write |
   | Infrastructure as Code | Read + Write |
   | Cloud Security Tools Download | Read |

5. Click **Add** and **copy both the Client ID and Client Secret** — you won't see the secret again.

---

## Step 2 — Create a Variable Group in Azure DevOps (1 minute)

1. In Azure DevOps, go to **Pipelines → Library**
2. Click **+ Variable group**
3. Name it exactly: `falcon-credentials`
4. Add the following variables:
   - `FALCON_CLIENT_ID` — paste your Client ID (mark as **secret**)
   - `FALCON_CLIENT_SECRET` — paste your Client Secret (mark as **secret**)
   - `FALCON_API_URL` — your regional API base URL (**required if your tenant is not US-1**):
     - US-1: omit this variable (scripts default to `https://api.crowdstrike.com`)
     - US-2: `https://api.us-2.crowdstrike.com`
     - EU-1: `https://api.eu-1.crowdstrike.com`
5. Click **Save**
6. Click the **Pipeline permissions** tab and authorize the pipeline(s) that will use this group

> **Why a variable group?** It keeps credentials out of YAML files and out of git history. The pipeline YAMLs in this repo reference `- group: falcon-credentials` — that's the only connection needed.

---

## Step 3 — Choose and Copy a Pipeline YAML (1 minute)

Copy the pipeline that fits your use case into your application repository:

| File | Use case |
|---|---|
| `azure-pipelines/combined-pipeline.yml` | Both IaC scan + image scan (recommended starting point) |
| `azure-pipelines/image-scan-pipeline.yml` | Container image scan only |
| `azure-pipelines/iac-scan-pipeline.yml` | IaC scan only |

```bash
# Example: copy the combined pipeline
cp azure-pipelines/combined-pipeline.yml <your-app-repo>/azure-pipelines.yml
```

Open the copied file and update the variables section at the top:

```yaml
variables:
  - group: falcon-credentials   # keep this — references your secret group
  - name: IMAGE_TAG
    value: 'myapp:$(Build.SourceVersion)'   # ← update to your image name
```

For the IaC pipeline, also update `IAC_PATH` if your IaC files are not in `iac/`.

---

## Step 4 — Create the Pipeline in Azure DevOps

Azure DevOps uses a multi-screen wizard to create a pipeline. Here is exactly what you will see and what to click at each step.

### 4a — Open the New Pipeline wizard

1. In your browser, go to your Azure DevOps organization:
   `https://dev.azure.com/<your-org>/<your-project>`
2. In the left sidebar, click **Pipelines** (the rocket icon)
3. Click **New pipeline** (blue button, top right)

### 4b — Choose where your code lives

The wizard asks **"Where is your code?"**. Select the option that matches where your application repository lives:

| If your repo is in… | Choose |
|---|---|
| Azure DevOps Repos | **Azure Repos Git** |
| GitHub | **GitHub** (you will be asked to authorize Azure DevOps) |
| Bitbucket Cloud | **Bitbucket Cloud** |
| Other Git | **Other Git** |

> If you chose GitHub, a browser popup will ask you to authorize Azure Pipelines — click **Authorize**. You may also need to select which repositories Azure DevOps is allowed to access.

### 4c — Select your repository

A list of repositories in your account appears. Click the repository where you placed the pipeline YAML file (the one you copied in Step 3).

### 4d — Configure the pipeline

The wizard asks **"Configure your pipeline"**. Do **not** choose "Starter pipeline" or "Maven" etc. Instead:

1. Scroll to the bottom of the options list
2. Click **Existing Azure Pipelines YAML file**

A panel slides in on the right:
- **Branch**: select the branch where you placed the YAML (usually `main`)
- **Path**: click the dropdown and select the path to your YAML file, e.g. `/azure-pipelines.yml`
- Click **Continue**

### 4e — Review and save

The YAML is displayed for review. You do not need to edit it here.

1. Click the **▾** dropdown arrow next to the **Run** button (top right)
2. Click **Save** — this creates the pipeline without immediately running it

> Tip: If you click **Run** directly, the pipeline starts immediately. That is fine, but saving first lets you verify the variable group is connected before the first run.

### 4f — Authorize the variable group (first run only)

The first time the pipeline runs it will pause and show a yellow banner:

> **"This pipeline needs permission to access a resource before this run can continue"**

1. Click **View** on the banner
2. Click **Permit** next to `falcon-credentials`
3. Click **Permit** again to confirm

This one-time step grants the pipeline access to your secrets. It will not appear on subsequent runs.

### 4g — Run the pipeline

1. In the left sidebar, click **Pipelines**
2. Find your new pipeline and click it
3. Click **Run pipeline** (top right) → **Run**

The pipeline run opens automatically. You will see each stage and job appear as colored blocks as they execute.

---

## Step 5 — Review Results

### Reading the pipeline run view

When you open a pipeline run you will see a diagram of stages and jobs with colored status indicators:

| Color | Meaning |
|---|---|
| Green (✓) | Passed |
| Red (✗) | Failed |
| Yellow (!) | Failed with warning |
| Blue (spinning) | Currently running |
| Grey | Waiting / not yet started |

Click any job box to open its log. Each step inside the job is listed on the left — click a step to jump to its log output.

If a step shows a red `##[error]` line, that is the descriptive gate message from the pipeline (e.g. "IaC scan found critical or high severity issues").

### Downloading scan artifacts

Each job publishes scan results as a pipeline artifact — this is the JSON and SARIF output from FCSCLI.

1. On the pipeline run page, click the **Artifacts** link near the top right (or the published artifact icon)
2. You will see artifact names like `iac-scan-results` and `image-scan-results`
3. Click an artifact name to browse its files, or click the download icon (⬇) to download a zip

> Artifacts are always published even when a scan finds issues, so you can review the findings without re-running the pipeline.

### Falcon Console results

Results uploaded with `--upload` appear in the Falcon Console under **Cloud Security → Scan Results**. This provides a persistent history across pipeline runs independent of Azure DevOps artifact retention.

---

## Common Issues

### "Authentication failed" (exit code 201)

Verify the variable group contents and that the pipeline has permission to use it:

1. **Pipelines → Library → falcon-credentials → Pipeline permissions** — confirm your pipeline is listed
2. Confirm `FALCON_CLIENT_ID` and `FALCON_CLIENT_SECRET` are marked as secret and contain the correct values
3. Check the Falcon Console URL to confirm your region and ensure `FALCON_API_URL` is set in the variable group accordingly (see Step 2).

### "Insufficient permissions" (exit code 202)

The API client is missing one or more required scopes. Go back to **Step 1** and confirm all four scopes are enabled with both Read and Write.

### "fcs command not found"

The `download-fcscli.sh` script places the binary in the current directory (`./fcs`). Ensure the scan steps that follow use `./fcs`, not just `fcs`. The pipeline YAMLs in this repo already do this.

### Scan timeout on large images

Increase the `--timeout` value in the scan step (default is 300 seconds):

```yaml
./fcs scan image $(IMAGE_TAG) \
  --format json \
  --output image-scan-results.json \
  --minimum-exprt high \
  --timeout 900        # ← increase as needed
```

---

## Next Steps

- [docs/configuration.md](docs/configuration.md) — All environment variables and CLI flags
- [docs/ci-cd-integration.md](docs/ci-cd-integration.md) — Exit code reference, artifact tips, performance optimization
- `examples/image-scan-examples.sh` — Additional image scanning patterns
- `examples/iac-scan-examples.sh` — Additional IaC scanning patterns and policy enforcement examples
