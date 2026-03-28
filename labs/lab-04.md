---
permalink: /labs/lab-04
title: "Lab 04 - Cloud Custodian: Runtime Resource Scanning"
description: "Scan live Azure resources for cost governance violations using Cloud Custodian."
---

## Overview

| | |
|---|---|
| **Duration** | 40 minutes |
| **Level** | Intermediate |
| **Prerequisites** | [Lab 01](lab-01.md) |

> [!IMPORTANT]
> This lab requires deployed Azure resources. Ensure at least apps 001, 003, and 004 are deployed before starting. If you have not deployed them, return to Lab 00, Exercise 0.5.

## Learning Objectives

By the end of this lab, you will be able to:

* Install and configure Cloud Custodian with the `c7n-azure` provider
* Review Cloud Custodian policies for tagging, orphan detection, right-sizing, and idle resources
* Run Cloud Custodian scans against live Azure resources
* Convert Cloud Custodian JSON output to SARIF using the `custodian-to-sarif.py` converter

## Exercises

### Exercise 4.1: Review Custodian Policies

You will walk through the 4 policy files in `src/config/custodian/` to understand what each one detects.

1. Open the `src/config/custodian/` directory and review the policy files listed below.

2. Each Cloud Custodian policy file follows the same structure:

   ```yaml
   policies:
     - name: policy-name        # Unique name for this rule
       resource: azure.type     # Azure resource type to scan
       filters:                 # Conditions that flag a violation
         - type: value
           key: properties.field
           value: some-value
   ```

3. Review the following policy reference table. Each row maps a policy file to the resource it scans and the violation it detects:

   | Policy File | Policy Name | Target Resource | Violation Detected |
   |---|---|---|---|
   | `tagging-compliance.yml` | `check-required-tags` | `azure.resourcegroup` | Missing governance tags |
   | `orphan-detection.yml` | `find-orphaned-disks` | `azure.disk` | `diskState == Unattached` |
   | `orphan-detection.yml` | `find-orphaned-nics` | `azure.networkinterface` | `virtualMachine == null` |
   | `orphan-detection.yml` | `find-orphaned-public-ips` | `azure.publicip` | `ipConfiguration == null` |
   | `right-sizing.yml` | `detect-oversized-vms` | `azure.vm` | D4s+ VMs in dev/test |
   | `right-sizing.yml` | `detect-oversized-plans` | `azure.appserviceplan` | P-tier/S3 plans in dev/test |
   | `idle-resources.yml` | `detect-no-autoshutdown` | `azure.vm` | Dev/test VMs not deallocated |

4. Open `src/config/custodian/tagging-compliance.yml` and examine how the `or` filter checks for any of the 7 required governance tags being absent:

   ```yaml
   policies:
     - name: check-required-tags
       resource: azure.resourcegroup
       filters:
         - or:
           - "tag:CostCenter": absent
           - "tag:Owner": absent
           - "tag:Environment": absent
           - "tag:Application": absent
           - "tag:Department": absent
           - "tag:Project": absent
           - "tag:ManagedBy": absent
   ```

5. Open `src/config/custodian/orphan-detection.yml` and note how each policy targets a different Azure resource type. The `find-orphaned-disks` policy looks for disks with `diskState == Unattached`, while `find-orphaned-nics` checks for NICs where `virtualMachine == null`.

6. Open `src/config/custodian/right-sizing.yml` and observe the two-filter pattern: the first filter matches oversized SKUs (D4s+, P-tier, S3), and the second filter restricts to dev/test environments using the `Environment` tag.

7. Open `src/config/custodian/idle-resources.yml` and review how it detects VMs in dev/test that are not deallocated.

![Cloud Custodian policy file](../images/lab-04/lab-04-custodian-policy.png)

> [!TIP]
> Cloud Custodian policies are declarative YAML. Unlike PSRule and Checkov which scan IaC files, Cloud Custodian queries **live Azure resources** through the Azure Resource Manager API. This means it catches violations that only appear at runtime — such as orphaned resources created outside of IaC.

### Exercise 4.2: Run Tagging Compliance

You will run the tagging compliance policy against your deployed Azure resources.

1. Create the output directory:

   ```bash
   mkdir -p output
   ```

2. Run the tagging compliance scan:

   ```bash
   custodian run -s output/ src/config/custodian/tagging-compliance.yml --cache-period 0
   ```

   The `-s output/` flag sets the output directory. The `--cache-period 0` flag disables caching so you always get fresh results.

3. Review the scan output. Cloud Custodian reports the number of resources matched by each policy.

4. Check the JSON output file:

   ```bash
   cat output/check-required-tags/resources.json
   ```

   Each entry in the array is an Azure resource group that is missing at least one of the 7 required governance tags. App 001 deploys resources with **zero tags**, so its resource group should appear.

![Tagging compliance scan output](../images/lab-04/lab-04-custodian-tags.png)

> [!NOTE]
> Cloud Custodian creates a subdirectory under `output/` named after the policy (for example, `output/check-required-tags/`). Each subdirectory contains a `resources.json` file with the matched resources and optional metadata files.

### Exercise 4.3: Run Orphan Detection

You will scan for orphaned resources that are incurring costs but not attached to any workload.

1. Run the orphan detection scan:

   ```bash
   custodian run -s output/ src/config/custodian/orphan-detection.yml --cache-period 0
   ```

2. This policy file contains 3 separate policies. Each one creates its own output subdirectory:
   - `output/find-orphaned-disks/resources.json`
   - `output/find-orphaned-nics/resources.json`
   - `output/find-orphaned-public-ips/resources.json`

3. Review the orphan results:

   ```bash
   cat output/find-orphaned-disks/resources.json
   cat output/find-orphaned-nics/resources.json
   cat output/find-orphaned-public-ips/resources.json
   ```

4. App 003 deploys unattached Public IPs, NICs, Managed Disks, and NSGs. You should see findings from this app's resource group in the output.

![Orphan detection scan output](../images/lab-04/lab-04-custodian-orphans.png)

> [!IMPORTANT]
> Orphaned resources are one of the most common sources of cloud waste. A single unattached managed disk can cost $5–$75 per month depending on the tier and size. Cloud Custodian can detect these automatically on a schedule.

### Exercise 4.4: Run Right-Sizing

You will scan for oversized resources in development and test environments.

1. Run the right-sizing scan:

   ```bash
   custodian run -s output/ src/config/custodian/right-sizing.yml --cache-period 0
   ```

2. Review the output files:

   ```bash
   cat output/detect-oversized-vms/resources.json
   cat output/detect-oversized-plans/resources.json
   ```

3. App 002 deploys a P3v3 App Service Plan for a development workload. The `detect-oversized-plans` policy should flag this as a violation because P-tier plans are excessive for dev/test environments.

4. App 004 deploys a D4s_v5 VM. The `detect-oversized-vms` policy should flag this if the resource group has a dev/test `Environment` tag.

![Right-sizing scan output](../images/lab-04/lab-04-custodian-rightsizing.png)

> [!TIP]
> Right-sizing policies work best when you enforce consistent environment tagging. The policies in this workshop only flag oversized resources in environments tagged as `Development`, `Dev`, or `Test`. Production resources are excluded by design.

### Exercise 4.5: Convert to SARIF

You will convert Cloud Custodian's JSON output to SARIF format for upload to the GitHub Security tab.

1. Create the reports directory:

   ```bash
   mkdir -p reports
   ```

2. Run the SARIF converter:

   ```bash
   python src/converters/custodian-to-sarif.py output/ reports/custodian.sarif --resource-group rg-finops-demo-001
   ```

   The `--resource-group` flag filters results to show only resources belonging to the specified resource group. In the automated pipeline, each matrix job passes its own resource group name.

3. Open the generated SARIF file and inspect its structure:

   ```bash
   cat reports/custodian.sarif
   ```

4. Verify that the SARIF file contains:
   - A `tool.driver` section with `name: "custodian-to-sarif"`
   - A `rules` array mapping Cloud Custodian policy names to SARIF rule IDs
   - A `results` array with findings that include `physicalLocation` pointing to `infra/main.bicep`

5. Try converting with a different resource group and compare the output:

   ```bash
   python src/converters/custodian-to-sarif.py output/ reports/custodian-003.sarif --resource-group rg-finops-demo-003
   ```

![Converted SARIF from custodian-to-sarif.py](../images/lab-04/lab-04-custodian-sarif.png)

> [!NOTE]
> The `custodian-to-sarif.py` converter adds `physicalLocation` with `artifactLocation` pointing to `infra/main.bicep`. This is required by GitHub Code Scanning — the SARIF spec allows logical-only locations, but GitHub rejects SARIF without a physical file path.

## Verification Checkpoint

Before proceeding, verify:

* [ ] Cloud Custodian ran at least 2 policies successfully
* [ ] JSON output generated in `output/` directory with matched resources
* [ ] SARIF file generated by `custodian-to-sarif.py` with valid structure
* [ ] Can explain Cloud Custodian policy structure and filter syntax

## Next Steps

Proceed to [Lab 05 — Infracost: Cost Estimation and Budgeting](lab-05.md).
