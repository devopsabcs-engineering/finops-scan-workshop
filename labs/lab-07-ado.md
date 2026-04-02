---
permalink: /labs/lab-07-ado
title: "Lab 07-ADO - ADO YAML Pipelines and Cost Gates"
description: "Build automated scanning pipelines, cost gates, and deployment workflows with Azure DevOps YAML Pipelines."
---

## Overview

| | |
|---|---|
| **Duration** | 50 minutes |
| **Level** | Advanced |
| **Prerequisites** | [Lab 02](lab-02.md), [Lab 03](lab-03.md), [Lab 04](lab-04.md), [Lab 05](lab-05.md), [Lab 06-ADO](lab-06-ado.md) |

## Learning Objectives

By the end of this lab, you will be able to:

* Build an ADO YAML pipeline with matrix strategy for multi-app scanning
* Configure workload identity federation (WIF) service connections
* Implement variable groups for centralized configuration
* Set up schedule triggers and environment approvals
* Create pipeline templates for reuse
* Link work items using `AB#` syntax

## Exercises

### Exercise 7.1: Review ADO Scan Pipeline

You will walk through the centralized scanning pipeline that runs all 4 tools across all 5 demo apps.

1. Open `.azuredevops/pipelines/finops-scan.yml` and review the overall architecture:

   ```text
   finops-scan.yml
   ├── Stage: Scan
   │   ├── Job: PSRule (strategy: matrix × 5 apps)
   │   ├── Job: Checkov (strategy: matrix × 5 apps)
   │   └── Job: Custodian (strategy: matrix × 5 apps)
   └── Stage: Upload
       └── Job: SARIF Upload (strategy: matrix × 5 apps)
   ```

2. Review the trigger configuration:

   ```yaml
   trigger: none

   schedules:
     - cron: '0 6 * * 1'
       displayName: 'Weekly Monday 06:00 UTC'
       branches:
         include:
           - main
   ```

   The pipeline runs on a weekly schedule and can be triggered manually. Unlike GitHub Actions `workflow_dispatch`, ADO pipelines with `trigger: none` are always available for manual runs from the UI or CLI.

3. Review the pool configuration:

   ```yaml
   pool:
     vmImage: 'ubuntu-latest'
   ```

4. Review the variables section. The pipeline references shared variable groups:

   ```yaml
   variables:
     - group: finops-oidc-config
     - group: finops-secrets
   ```

   Variable groups centralize configuration across multiple pipelines. The `finops-oidc-config` group stores WIF-related values (Client ID, Tenant ID, Subscription ID), and `finops-secrets` stores sensitive values.

5. Review the matrix strategy used by each scan job:

   ```yaml
   strategy:
     matrix:
       app-001:
         appId: '001'
       app-002:
         appId: '002'
       app-003:
         appId: '003'
       app-004:
         appId: '004'
       app-005:
         appId: '005'
   ```

   This creates 5 parallel jobs per scanner — one for each demo app. ADO expands the matrix into individual jobs named `PSRule app-001`, `PSRule app-002`, and so on.

6. Compare the ADO matrix syntax with GitHub Actions:

   | Aspect | GitHub Actions | Azure DevOps |
   |--------|---------------|--------------|
   | Syntax | `matrix: { app: ['001','002'] }` | `matrix: { app-001: { appId: '001' } }` |
   | Access | `${{ matrix.app }}` | `$(appId)` |
   | Naming | Auto-generated (e.g., `app=001`) | Key name (e.g., `app-001`) |

![Scan pipeline YAML](../images/lab-07-ado/lab-07-ado-scan-pipeline.png)

> [!TIP]
> ADO matrix jobs run in parallel by default. With 3 scanners × 5 apps = 15 scan jobs + 5 upload jobs, the entire scan completes in the time of the slowest individual job — the same parallelism model as GitHub Actions.

### Exercise 7.2: WIF Service Connection Setup

You will review the workload identity federation (WIF) service connections that authenticate ADO pipelines to Azure.

1. Navigate to **Project Settings → Service connections** in the FinOps project.

2. Review the 6 WIF service connections:

   | Connection Name | Purpose |
   |----------------|---------|
   | `finops-scanner-ado` | Main scanner pipeline authentication |
   | `finops-app-001` | Demo app 001 deployment |
   | `finops-app-002` | Demo app 002 deployment |
   | `finops-app-003` | Demo app 003 deployment |
   | `finops-app-004` | Demo app 004 deployment |
   | `finops-app-005` | Demo app 005 deployment |

3. Click on `finops-scanner-ado` to inspect the configuration. A WIF service connection uses:
   - **Subscription ID** — the target Azure subscription
   - **Service Principal (App Registration)** — the Azure AD app with federated credentials
   - **Tenant ID** — the Azure AD tenant
   - **Workload Identity Federation** — instead of client secrets, ADO exchanges its pipeline token for an Azure token

4. Compare WIF with the GitHub OIDC approach from [Lab 07 Exercise 7.2](lab-07.md#exercise-72-oidc-setup):

   | Aspect | GitHub OIDC | ADO WIF |
   |--------|------------|---------|
   | Permission | `id-token: write` in workflow | Service connection assigned to pipeline |
   | Configuration | Federated credential with repo subject | WIF service connection in Project Settings |
   | Secrets | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` as repo secrets | Values stored in the service connection |
   | Token lifetime | Short-lived (job duration) | Short-lived (job duration) |

5. List service connections from the command line:

   ```bash
   az devops service-endpoint list \
     --organization https://dev.azure.com/MngEnvMCAP675646 \
     --project FinOps \
     --output table
   ```

![WIF service connection setup](../images/lab-07-ado/lab-07-ado-wif-setup.png)

> [!IMPORTANT]
> Workload identity federation eliminates the need for client secrets in ADO pipelines. The pipeline runtime exchanges its ADO-issued token for an Azure AD token using the federated trust. No long-lived credentials are stored in ADO variable groups or service connections.

### Exercise 7.3: Trigger Scan Pipeline

You will trigger the finops-scan pipeline manually and monitor its execution.

1. Trigger the pipeline from the command line:

   ```bash
   az pipelines run \
     --name finops-scan \
     --organization https://dev.azure.com/MngEnvMCAP675646 \
     --project FinOps
   ```

2. Alternatively, trigger from the ADO web UI:
   - Navigate to **Pipelines → Pipelines**
   - Find the **finops-scan** pipeline
   - Click **Run pipeline**
   - Select the `main` branch
   - Click **Run**

3. Monitor the pipeline execution. Click on the running pipeline to see the stages and jobs.

4. Expand the **Scan** stage to see the matrix jobs. You should see 15 jobs:
   - 5 PSRule scan jobs
   - 5 Checkov scan jobs
   - 5 Cloud Custodian scan jobs

5. Expand an individual job to view the step-level logs. Each scan job:
   - Checks out the scanner configuration
   - Checks out the target demo app repository
   - Runs the scanner tool
   - Publishes the SARIF file as a build artifact

6. Wait for the scan stage to complete. PSRule and Checkov jobs typically finish in 1–2 minutes. Cloud Custodian jobs may take longer because they query live Azure resources.

![ADO pipeline runs page](../images/lab-07-ado/lab-07-ado-pipeline-run.png)

![ADO pipeline with matrix jobs expanded](../images/lab-07-ado/lab-07-ado-matrix-jobs.png)

> [!NOTE]
> If Cloud Custodian jobs fail with authentication errors, verify that the `finops-scanner-ado` service connection is configured correctly (Exercise 7.2) and that the service principal has `Reader` role on the target subscription.

### Exercise 7.4: Review Pipeline Results

You will inspect the SARIF artifacts and variable group configuration after the pipeline completes.

1. After the pipeline completes, click on the run summary.

2. Navigate to the **Artifacts** section of the pipeline run. You should see SARIF artifacts for each app and scanner combination (for example, `sarif-psrule-001`, `sarif-checkov-002`).

3. Download a SARIF artifact and verify it contains findings:
   - Click on an artifact name
   - Download and open the `.sarif` file
   - Verify it has `runs[].results[]` with at least one finding

4. Review the variable groups used by the pipeline:
   - Navigate to **Pipelines → Library**
   - Review the 3 variable groups:

   | Variable Group | Purpose |
   |---------------|---------|
   | `finops-oidc-config` | WIF Client ID, Tenant ID, Subscription ID |
   | `finops-secrets` | Sensitive values (PATs, connection strings) |
   | `wiki-access` | Wiki publishing credentials |

5. Click on `finops-oidc-config` to see the stored variables. These are referenced in the pipeline YAML as `$(variableName)`.

![ADO variable groups page](../images/lab-07-ado/lab-07-ado-variable-groups.png)

> [!TIP]
> Variable groups in ADO are equivalent to GitHub repository secrets and variables combined. You can mark individual values as secret (encrypted, masked in logs) or leave them as plain text. Variable groups can be shared across multiple pipelines.

### Exercise 7.5: Cost Gate Branch Policy

You will review the cost gate pipeline and configure it as a branch policy for pull requests.

1. Open `.azuredevops/pipelines/finops-cost-gate.yml`. This pipeline:
   - Triggers on pull requests targeting the `main` branch
   - Runs `infracost diff` to compare the PR branch cost against the `main` branch baseline
   - Posts a cost summary comment on the PR

2. Review the pipeline trigger:

   ```yaml
   trigger: none

   pr:
     branches:
       include:
         - main
   ```

   Unlike the scan pipeline, this pipeline triggers automatically on PRs. In ADO, you can also configure it as a **build validation** branch policy for additional enforcement.

3. Configure the cost gate as a branch policy:
   - Navigate to **Repos → Branches**
   - Click the `...` menu on the `main` branch
   - Select **Branch policies**
   - Under **Build Validation**, click **Add build policy**
   - Select the **finops-cost-gate** pipeline
   - Set **Trigger** to **Automatic**
   - Set **Policy requirement** to **Required**
   - Click **Save**

4. Now every pull request targeting `main` must pass the cost gate before it can be completed. If a PR increases monthly costs beyond the threshold, the policy blocks the merge.

5. Compare with the GitHub Actions approach from [Lab 07 Exercise 7.5](lab-07.md#exercise-75-cost-gate-pr):

   | Aspect | GitHub Actions | Azure DevOps |
   |--------|---------------|--------------|
   | Trigger | `on: pull_request` | `pr: branches: include` + branch policy |
   | Enforcement | Status check (required) | Build validation policy (required) |
   | Comment | Infracost `--behavior update` | Infracost `--behavior update` |
   | Override | Bypass branch protection (admin) | Override branch policy (with permissions) |

![ADO PR with Infracost comment](../images/lab-07-ado/lab-07-ado-cost-gate-pr.png)

> [!TIP]
> Branch policies in ADO are the equivalent of GitHub branch protection rules. Both enforce quality gates before code reaches the main branch. The cost gate ensures no PR lands without a cost impact review.

### Exercise 7.6: Deploy and Teardown

You will review the deploy and teardown pipelines that manage the demo app lifecycle.

1. Open `.azuredevops/pipelines/deploy-all.yml`. The deploy pipeline has 2 stages:

   ```text
   deploy-all.yml
   ├── Stage 1: Deploy Storage
   │   └── Job: Create shared storage account
   └── Stage 2: Deploy Apps
       ├── Job: Deploy app-001 (template)
       ├── Job: Deploy app-002 (template)
       ├── Job: Deploy app-003 (template)
       ├── Job: Deploy app-004 (template)
       └── Job: Deploy app-005 (template)
   ```

   Stage 2 uses pipeline templates (`templates/deploy-app.yml`) to avoid repeating the same deployment steps 5 times.

2. Open `.azuredevops/pipelines/teardown-all.yml`. The teardown pipeline runs sequentially with environment approvals:

   ```text
   teardown-all.yml
   ├── Job: Teardown app-005 (environment: production)
   ├── Job: Teardown app-004 (environment: production)
   ├── Job: Teardown app-003 (environment: production)
   ├── Job: Teardown app-002 (environment: production)
   ├── Job: Teardown app-001 (environment: production)
   └── Job: Teardown storage (environment: production)
   ```

3. Review the environment approval gate:
   - Navigate to **Pipelines → Environments**
   - Click on the **production** environment
   - Review the **Approvals and checks** tab
   - The environment requires at least 1 approval before any job targeting it can proceed

4. Trigger the deploy pipeline:

   ```bash
   az pipelines run \
     --name deploy-all \
     --organization https://dev.azure.com/MngEnvMCAP675646 \
     --project FinOps
   ```

5. After deployment completes, verify the resources:

   ```bash
   az group list --query "[?starts_with(name, 'rg-finops-demo')].[name, location]" -o table
   ```

6. When you are ready to tear down, trigger the teardown pipeline:

   ```bash
   az pipelines run \
     --name teardown-all \
     --organization https://dev.azure.com/MngEnvMCAP675646 \
     --project FinOps
   ```

7. Navigate to the pipeline run in the ADO web UI and approve each environment deployment when prompted.

![ADO environment approval gate](../images/lab-07-ado/lab-07-ado-environment.png)

![ADO deploy pipeline runs page](../images/lab-07-ado/lab-07-ado-deploy-teardown.png)

> [!IMPORTANT]
> The teardown pipeline uses ADO environment approvals as a safety gate. This is the ADO equivalent of GitHub Actions environment protection rules. Always require approvals for destructive operations in production FinOps workflows.

### Exercise 7.7: Work Item Linking with AB#

You will learn how to link Git commits to Azure DevOps work items using the `AB#` syntax.

1. ADO uses the `AB#` prefix to link commits to work items. When you include `AB#{work-item-id}` in a commit message, ADO automatically creates a link between the commit and the work item.

2. Create a test commit with a work item reference:

   ```bash
   git commit -m "feat: add cost gate pipeline AB#1234"
   ```

   Replace `1234` with an actual work item ID from the `MngEnvMCAP675646/FinOps` project.

3. Push the commit:

   ```bash
   git push
   ```

4. Navigate to the work item in ADO Boards. Under the **Development** section, you should see the linked commit.

5. To auto-close a work item when a PR merges, use `Fixes AB#{id}` in the commit message or PR description:

   ```bash
   git commit -m "fix: update SARIF upload path Fixes AB#1235"
   ```

6. Review the full branching and commit workflow defined in the project:

   | Step | Convention |
   |------|-----------|
   | Branch naming | `feature/{work-item-id}-short-description` |
   | Commit message | Include `AB#{id}` to link work items |
   | Auto-close | Use `Fixes AB#{id}` to close on merge |
   | PR description | Reference `AB#{id}` for traceability |

7. Compare with GitHub issue linking:

   | Aspect | GitHub | Azure DevOps |
   |--------|--------|--------------|
   | Link syntax | `#123` or `org/repo#123` | `AB#1234` |
   | Auto-close | `Fixes #123`, `Closes #123` | `Fixes AB#1234` |
   | PR linking | Automatic from branch name or description | Automatic from `AB#` in commit or PR |
   | Work items | Issues and Projects | Boards (Epics → Features → User Stories/Bugs) |

> [!NOTE]
> The `AB#` linking syntax works through the GitHub and Azure DevOps integration. Commits pushed to GitHub repositories that are connected to ADO automatically resolve `AB#` references and create bidirectional links.

## Verification Checkpoint

Before completing the ADO track, verify:

* [ ] `finops-scan` pipeline ran successfully with matrix jobs across all 5 apps
* [ ] SARIF artifacts uploaded to ADO Advanced Security for at least one app
* [ ] Cost gate pipeline configured as a branch policy on `main`
* [ ] Can explain WIF service connections and how they replace stored credentials
* [ ] Can explain `AB#` work item linking syntax and auto-close behaviour

## Congratulations

You have completed the ADO track of the FinOps Cost Governance Scanner Workshop. Here is a summary of the full workshop:

| Lab | What You Learned |
|-----|------------------|
| **Lab 00** | Set up the development environment with all 4 scanner tools |
| **Lab 01** | Identified the 5 demo app FinOps violations and the 7 required governance tags |
| **Lab 02** | Ran PSRule against Bicep templates for Azure best practice analysis |
| **Lab 03** | Ran Checkov for security and CIS benchmark scanning |
| **Lab 04** | Ran Cloud Custodian against live Azure resources for runtime violation detection |
| **Lab 05** | Used Infracost to estimate costs and compare infrastructure changes |
| **Lab 06** | Understood the SARIF format and uploaded results to GitHub Security Tab |
| **Lab 06-ADO** | Uploaded SARIF results to ADO Advanced Security and compared platforms |
| **Lab 07** | Built automated pipelines with GitHub Actions, OIDC, and PR cost gates |
| **Lab 07-ADO** | Built ADO YAML pipelines with WIF, variable groups, and branch policies |

You now have the skills to implement a complete FinOps scanning platform on **both** GitHub and Azure DevOps:

* **Scan IaC templates** before deployment (PSRule, Checkov, Infracost)
* **Scan live resources** after deployment (Cloud Custodian)
* **Produce unified SARIF output** for all tools
* **Integrate with GitHub Security Tab** or **ADO Advanced Security** for centralised alert management
* **Block expensive changes** with PR cost gates and branch policies
* **Run automatically** on a schedule via GitHub Actions or ADO YAML Pipelines
* **Link work items** using `AB#` syntax for full traceability

Return to the [workshop home page](../index.md).

> [!NOTE]
> For the GitHub variant of this lab, see [Lab 07 — GitHub Actions Pipelines and Cost Gates](lab-07.md).
