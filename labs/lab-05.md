---
permalink: /labs/lab-05
title: "Lab 05 - Infracost: Cost Estimation and Budgeting"
description: "Estimate infrastructure costs from Bicep templates and set up PR cost gates."
---

## Overview

| | |
|---|---|
| **Duration** | 35 minutes |
| **Level** | Intermediate |
| **Prerequisites** | [Lab 01](lab-01.md) |

## Learning Objectives

By the end of this lab, you will be able to:

* Configure Infracost with an API key and project settings
* Run `infracost breakdown` to estimate monthly infrastructure costs from Bicep templates
* Use `infracost diff` to compare cost changes between Bicep revisions
* Convert Infracost JSON output to SARIF using the `infracost-to-sarif.py` converter
* Understand how the PR cost gate workflow blocks expensive changes

## Exercises

### Exercise 5.1: Configure Infracost

You will set up Infracost with an API key and review the project configuration.

1. Register for a free Infracost API key at [infracost.io](https://www.infracost.io/) if you have not already.

2. Configure the API key:

   ```bash
   infracost configure set api_key YOUR_API_KEY
   ```

3. Verify the configuration:

   ```bash
   infracost configure get api_key
   ```

4. Open `src/config/infracost.yml` and review the project configuration:

   ```yaml
   version: 0.1
   projects:
     - path: infra/
       name: finops-demo-app
   ```

   This tells Infracost to scan the `infra/` directory within each demo app for Bicep or Terraform templates.

![Infracost configuration](../images/lab-05/lab-05-infracost-config.png)

> [!TIP]
> Infracost uses cloud pricing APIs to estimate costs. It does not require deployed resources — it analyses IaC templates and maps resource types to current pricing data. This makes it ideal for **pre-deployment** cost checks in CI/CD pipelines.

### Exercise 5.2: Cost Breakdown — App 002

You will generate a cost breakdown for the oversized resources demo app.

1. Create the reports directory:

   ```bash
   mkdir -p reports
   ```

2. Run the Infracost breakdown against app 002:

   ```bash
   infracost breakdown --path finops-demo-app-002/infra/ --format json --out-file reports/infracost.json
   ```

3. View the human-readable summary:

   ```bash
   infracost breakdown --path finops-demo-app-002/infra/
   ```

   The table output shows each resource, its SKU or tier, and the estimated monthly cost.

4. Open `reports/infracost.json` and review the structure:
   - **`projects`** — array of scanned IaC paths
   - **`totalMonthlyCost`** — total estimated monthly cost across all resources
   - **`resources`** — individual resource cost breakdowns with line-item pricing

5. Note the cost of the P3v3 App Service Plan. This is the oversized resource that app 002 intentionally deploys — a premium tier plan for a development workload.

![Infracost breakdown output](../images/lab-05/lab-05-infracost-breakdown.png)

> [!NOTE]
> App 002 uses a **P3v3** App Service Plan and **Premium** storage. These are expensive tiers intended for production-grade workloads. Infracost makes the monthly cost immediately visible so you can make informed decisions before deploying.

### Exercise 5.3: Cost Diff

You will modify a SKU in app 002's Bicep template and use `infracost diff` to see the cost impact.

1. Open `finops-demo-app-002/infra/main.bicep` in your editor.

2. Find the App Service Plan SKU and change it from `P3v3` to `B1` (Basic tier):

   ```bicep
   // Before:
   // sku: { name: 'P3v3', tier: 'PremiumV3' }

   // After:
   sku: { name: 'B1', tier: 'Basic' }
   ```

3. Run `infracost diff` to compare the cost of the modified template against the baseline:

   ```bash
   infracost diff --path finops-demo-app-002/infra/ --compare-to reports/infracost.json
   ```

4. Review the diff output. It shows:
   - Resources with **increased** cost (▲)
   - Resources with **decreased** cost (▼)
   - The **net monthly change** from the modification

5. The diff should show a significant cost reduction from downgrading P3v3 to B1 — this demonstrates why right-sizing matters for FinOps governance.

6. **Revert** the change to `main.bicep` so it does not affect later labs:

   ```bash
   git checkout finops-demo-app-002/infra/main.bicep
   ```

![Infracost diff output](../images/lab-05/lab-05-infracost-diff.png)

> [!IMPORTANT]
> Always revert intentional Bicep changes after completing this exercise. The demo apps are designed with specific violations, and modifying them permanently can affect Labs 06 and 07.

### Exercise 5.4: Convert to SARIF

You will convert the Infracost JSON output to SARIF format.

1. Run the SARIF converter:

   ```bash
   python src/converters/infracost-to-sarif.py reports/infracost.json reports/infracost.sarif
   ```

2. Open the generated SARIF file:

   ```bash
   cat reports/infracost.sarif
   ```

3. Review the SARIF structure:
   - The `tool.driver.name` is set to `infracost-to-sarif`
   - Each resource with a monthly cost above a threshold is reported as a finding
   - The `message.text` includes the estimated monthly cost for the resource
   - The `physicalLocation` points to the Bicep file that defines the resource

4. This SARIF file can be uploaded to the GitHub Security tab alongside PSRule, Checkov, and Cloud Custodian results to provide a unified view of cost governance findings.

![Converted SARIF from Infracost](../images/lab-05/lab-05-infracost-sarif.png)

### Exercise 5.5: Review Cost Gate Workflow

You will walk through the GitHub Actions workflow that blocks expensive infrastructure changes in pull requests.

1. Open `.github/workflows/finops-cost-gate.yml` and review the workflow structure:

   ```yaml
   name: FinOps Cost Gate

   on:
     pull_request:
       branches: [main]
       paths: ['infra/**']
   ```

   The workflow triggers on pull requests to `main` that modify files under `infra/`.

2. Review the workflow steps:
   - **Setup Infracost** — installs the Infracost CLI with the API key from repository secrets
   - **Generate Infracost baseline** — runs `infracost breakdown` to capture the current cost
   - **Run Infracost diff** — compares the PR changes against the baseline
   - **Post PR comment** — uses `infracost comment github` to add a cost summary comment to the PR
   - **Convert to SARIF** — generates a SARIF file from the Infracost diff output
   - **Upload SARIF** — uploads the SARIF file to the GitHub Security tab

3. Note the `infracost comment github` command:

   ```yaml
   infracost comment github \
     --path infracost-output.json \
     --repo ${{ github.repository }} \
     --pull-request ${{ github.event.pull_request.number }} \
     --github-token ${{ secrets.GITHUB_TOKEN }} \
     --behavior update
   ```

   The `--behavior update` flag updates the existing comment instead of creating duplicates on each push.

4. This workflow creates a **cost gate** — reviewers can see the cost impact of infrastructure changes directly in the PR before approving.

![Cost gate workflow YAML](../images/lab-05/lab-05-cost-gate-workflow.png)

> [!TIP]
> In production, you can extend the cost gate to **fail the PR check** if costs exceed a threshold. Add a step that reads `totalMonthlyCost` from the Infracost JSON and compares it against a budget limit.

## Verification Checkpoint

Before proceeding, verify:

* [ ] Infracost authenticated and returning cost estimates
* [ ] Cost breakdown generated for at least 1 demo app
* [ ] Observed cost difference using `infracost diff` after modifying a SKU
* [ ] SARIF file generated from Infracost output

## Next Steps

Proceed to [Lab 06 — SARIF Output and GitHub Security Tab](lab-06.md).
