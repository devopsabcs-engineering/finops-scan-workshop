---
layout: default
title: Home
nav_order: 0
permalink: /
---

<p align="center">
  <img src="assets/branding/logo-128.png" alt="Agentic Accelerator Framework" width="100">
</p>

# FinOps Cost Governance Workshop

Welcome to the **FinOps Cost Governance Workshop** — a hands-on, progressive workshop that teaches you how to scan Azure infrastructure for cost governance violations using four open-source tools: PSRule, Checkov, Cloud Custodian, and Infracost.

All results are normalized to [SARIF v2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html) for unified reporting in GitHub Advanced Security or Azure DevOps Advanced Security.

> [!NOTE]
> This workshop is part of the [Agentic Accelerator Framework](https://github.com/devopsabcs-engineering/agentic-accelerator-framework).

## Architecture

```mermaid
graph LR
    subgraph "IaC Scanners"
        PSRule[PSRule for Azure]
        Checkov[Checkov]
    end

    subgraph "Runtime Scanners"
        Custodian[Cloud Custodian]
        Infracost[Infracost]
    end

    subgraph "Demo Apps"
        App1[App 001: Missing Tags]
        App2[App 002: Oversized SKUs]
        App3[App 003: Orphaned Resources]
        App4[App 004: No Auto-Shutdown]
        App5[App 005: Redundant/Expensive]
    end

    App1 --> PSRule
    App2 --> PSRule
    App3 --> Custodian
    App4 --> Custodian
    App5 --> Infracost

    PSRule -->|Native SARIF| SARIF[SARIF v2.1.0]
    Checkov -->|Native SARIF| SARIF
    Custodian -->|JSON → Converter| SARIF
    Infracost -->|JSON → Converter| SARIF

    SARIF --> Security[GitHub Security Tab]
    SARIF --> PowerBI[Power BI Dashboard]
```

## Tool Stack

| Tool | Focus | SARIF Output | License |
|------|-------|-------------|---------|
| PSRule for Azure | WAF Cost Optimization rules on Bicep/ARM | Native | MIT |
| Checkov | 1,000+ multi-cloud IaC policies | Native | Apache 2.0 |
| Cloud Custodian | Orphans, tagging, right-sizing on live resources | Converted | Apache 2.0 |
| Infracost | Pre-deployment cost estimates | Converted | Apache 2.0 |

## Prerequisites

- **GitHub account** with access to create repositories
- **Azure subscription** (required for Labs 04, 05, 07; free tier works)
- **VS Code** with the Bicep and PowerShell extensions
- **Tools** (installed during Lab 00):
  - Azure CLI
  - GitHub CLI
  - PowerShell 7+
  - PSRule and PSRule.Rules.Azure module
  - Checkov (`pip install checkov`)
  - Cloud Custodian (`pip install c7n c7n-azure`)
  - Infracost CLI

See [Lab 00: Prerequisites](labs/lab-00-setup.md) for detailed installation instructions.

## Labs

| # | Lab | Duration | Level |
|---|-----|----------|-------|
| 00 | [Prerequisites](labs/lab-00-setup.md) | 30 min | Beginner |
| 01 | [Explore Demo Apps](labs/lab-01.md) | 25 min | Beginner |
| 02 | [PSRule](labs/lab-02.md) | 35 min | Intermediate |
| 03 | [Checkov](labs/lab-03.md) | 30 min | Intermediate |
| 04 | [Cloud Custodian](labs/lab-04.md) | 40 min | Intermediate |
| 05 | [Infracost](labs/lab-05.md) | 35 min | Intermediate |
| 06 | [SARIF + GitHub Security Tab](labs/lab-06.md) | 30 min | Intermediate |
| 06-ADO | [SARIF + ADO Advanced Security](labs/lab-06-ado.md) | 35 min | Intermediate |
| 07 | [GitHub Actions + Cost Gates](labs/lab-07.md) | 45 min | Advanced |
| 07-ADO | [ADO Pipelines + Cost Gates](labs/lab-07-ado.md) | 50 min | Advanced |

## Workshop Schedule

### Half-Day (3.5 hours)

| Time | Activity |
|------|----------|
| 0:00 – 0:30 | Lab 00: Prerequisites |
| 0:30 – 0:55 | Lab 01: Explore Demo Apps |
| 0:55 – 1:30 | Lab 02: PSRule |
| 1:30 – 2:00 | Lab 03: Checkov |
| 2:00 – 2:15 | Break |
| 2:15 – 2:45 | Lab 06: SARIF + GitHub Security Tab (or Lab 06-ADO) |

### Full-Day (7 hours)

| Time | Activity |
|------|----------|
| 0:00 – 0:30 | Lab 00: Prerequisites |
| 0:30 – 0:55 | Lab 01: Explore Demo Apps |
| 0:55 – 1:30 | Lab 02: PSRule |
| 1:30 – 2:00 | Lab 03: Checkov |
| 2:00 – 2:40 | Lab 04: Cloud Custodian |
| 2:40 – 2:55 | Break |
| 2:55 – 3:30 | Lab 05: Infracost |
| 3:30 – 4:00 | Lab 06: SARIF + GitHub Security Tab |
| 4:00 – 4:35 | Lab 06-ADO: SARIF + ADO Advanced Security |
| 4:35 – 4:50 | Break |
| 4:50 – 5:35 | Lab 07: GitHub Actions + Cost Gates |
| 5:35 – 6:25 | Lab 07-ADO: ADO Pipelines + Cost Gates |

## Lab Dependency Diagram

```mermaid
graph LR
    L00[Lab 00: Setup] --> L01[Lab 01: Demo Apps]
    L01 --> L02[Lab 02: PSRule]
    L01 --> L03[Lab 03: Checkov]
    L01 --> L04[Lab 04: Cloud Custodian]
    L01 --> L05[Lab 05: Infracost]
    L02 --> L06[Lab 06: SARIF + GitHub Security Tab]
    L03 --> L06
    L04 --> L06
    L05 --> L06
    L02 --> L06A[Lab 06-ADO: SARIF + ADO AdvSec]
    L03 --> L06A
    L04 --> L06A
    L05 --> L06A
    L06 --> L07[Lab 07: GitHub Actions + Cost Gates]
    L06A --> L07A[Lab 07-ADO: ADO Pipelines + Cost Gates]

    classDef beginner fill:#107C10,stroke:#0b5e0b,color:#fff
    classDef intermediate fill:#0078D4,stroke:#005a9e,color:#fff
    classDef advanced fill:#D13438,stroke:#a4262c,color:#fff

    class L00,L01 beginner
    class L02,L03,L04,L05,L06,L06A intermediate
    class L07,L07A advanced
```

## Delivery Tiers

| Tier | Platform | Labs | Duration | Azure Required |
|------|----------|------|----------|---------------|
| Half-Day (GitHub) | GitHub | 00, 01, 02, 03, 06 | ~3.5 hours | No |
| Half-Day (ADO) | ADO | 00, 01, 02, 03, 06-ADO | ~3.5 hours | No |
| Full-Day (GitHub) | GitHub | 00–07 (all GitHub) | ~7.25 hours | Yes |
| Full-Day (ADO) | ADO | 00–05, 06-ADO, 07-ADO | ~7.75 hours | Yes |
| Full-Day (Dual) | Both | 00–05, 06, 06-ADO, 07, 07-ADO | ~9.25 hours | Yes |

## Getting Started

1. **Fork or use this template** to create your own workshop instance.
2. Complete [Lab 00: Prerequisites](labs/lab-00-setup.md) to set up your environment.
3. Work through the labs in order — each lab builds on the previous one.

> **Tip**: This workshop is designed for GitHub Codespaces. Click **Code → Codespaces → New codespace** to get a pre-configured environment with all tools installed.

## License

This project is licensed under the [MIT License](LICENSE).
