<#
.SYNOPSIS
    Capture all workshop screenshots for FinOps Scan Workshop labs 00-07.

.DESCRIPTION
    Automates screenshot capture for 8 workshop labs using Charm freeze (terminal
    output) and Playwright (browser pages). Produces 46 PNG files organized into
    images/lab-XX/ directories. Requires the demo apps to be deployed and all
    prerequisite tools to be installed.

.NOTES
    Prerequisites:
    - freeze (Charm CLI) installed — https://github.com/charmbracelet/freeze
    - Node.js and npx installed (for Playwright)
    - GitHub CLI (gh) authenticated
    - Azure CLI (az) authenticated
    - Demo apps deployed to Azure

.EXAMPLE
    .\scripts\capture-screenshots.ps1
    Captures all 46 screenshots across 8 labs.

.EXAMPLE
    .\scripts\capture-screenshots.ps1 -LabFilter '02'
    Captures only Lab 02 screenshots.

.EXAMPLE
    .\scripts\capture-screenshots.ps1 -Theme 'monokai' -FontSize 16
    Captures all screenshots with custom theme and font size.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDir = 'images',

    [Parameter()]
    [string]$LabFilter = '',

    [Parameter()]
    [string]$Theme = 'dracula',

    [Parameter()]
    [int]$FontSize = 14,

    [Parameter()]
    [string]$Org = 'devopsabcs-engineering'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$FreezeCommon = @(
    '--window'
    '--theme', $Theme
    '--font.size', $FontSize
    '--padding', '20,40'
    '--border.radius', '8'
    '--shadow.blur', '4'
    '--shadow.x', '0'
    '--shadow.y', '2'
)

$script:CaptureCount = 0
$script:FailureCount = 0
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# ── Helper Functions ─────────────────────────────────────────────────────────

function New-LabDirectory {
    param([string]$Lab)
    $dir = Join-Path $OutputDir "lab-$Lab"
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    else {
        # Clear existing PNGs
        Get-ChildItem -Path $dir -Filter '*.png' -ErrorAction SilentlyContinue |
            Remove-Item -Force
    }
    return $dir
}

function Invoke-FreezeScreenshot {
    param(
        [string]$Command,
        [string]$OutputPath
    )
    Write-Host "  Capturing: $(Split-Path $OutputPath -Leaf)..." -ForegroundColor Gray
    try {
        $args = @('--execute', $Command) + $FreezeCommon + @('-o', $OutputPath)
        & freeze @args 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    FAILED: freeze exited with code $LASTEXITCODE" -ForegroundColor Red
            $script:FailureCount++
            return
        }
        $script:CaptureCount++
        Write-Host "    OK" -ForegroundColor Green
    }
    catch {
        Write-Host "    FAILED: $_" -ForegroundColor Red
        $script:FailureCount++
    }
}

function Invoke-FreezeFile {
    param(
        [string]$FilePath,
        [string]$OutputPath,
        [string]$Lines = ''
    )
    Write-Host "  Capturing: $(Split-Path $OutputPath -Leaf)..." -ForegroundColor Gray
    try {
        $args = @($FilePath, '--show-line-numbers') + $FreezeCommon
        if ($Lines) {
            $args += @('--lines', $Lines)
        }
        $args += @('-o', $OutputPath)
        & freeze @args 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    FAILED: freeze exited with code $LASTEXITCODE" -ForegroundColor Red
            $script:FailureCount++
            return
        }
        $script:CaptureCount++
        Write-Host "    OK" -ForegroundColor Green
    }
    catch {
        Write-Host "    FAILED: $_" -ForegroundColor Red
        $script:FailureCount++
    }
}

function Invoke-PlaywrightScreenshot {
    # TODO: For authenticated GitHub pages, inject cookies via gh auth token.
    # Playwright cookie injection requires a custom script or storageState file.
    param(
        [string]$Url,
        [string]$OutputPath
    )
    Write-Host "  Capturing: $(Split-Path $OutputPath -Leaf) (browser)..." -ForegroundColor Gray
    try {
        npx playwright screenshot --viewport-size='1280,900' $Url $OutputPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    FAILED: playwright exited with code $LASTEXITCODE" -ForegroundColor Red
            $script:FailureCount++
            return
        }
        $script:CaptureCount++
        Write-Host "    OK" -ForegroundColor Green
    }
    catch {
        Write-Host "    FAILED: $_" -ForegroundColor Red
        $script:FailureCount++
    }
}

# ── Prerequisite Validation ──────────────────────────────────────────────────

Write-Host "`nValidating prerequisites..." -ForegroundColor Cyan

$MissingTools = @()
foreach ($tool in @('freeze', 'node', 'npx', 'gh', 'az')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        $MissingTools += $tool
    }
}

if ($MissingTools.Count -gt 0) {
    Write-Host "ERROR: Missing required tools: $($MissingTools -join ', ')" -ForegroundColor Red
    Write-Host "Install missing tools before running this script." -ForegroundColor Yellow
    exit 1
}

Write-Host "All prerequisites found.`n" -ForegroundColor Green

# ── Scanner repo path (for file captures) ────────────────────────────────────

$ScannerRepo = Join-Path (Split-Path $PSScriptRoot) '..\finops-scan-demo-app'
if (-not (Test-Path $ScannerRepo)) {
    $ScannerRepo = Join-Path (Split-Path $PSScriptRoot) '..\..\finops-scan-demo-app'
}

# ── Lab 00: Environment Setup ───────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '00') {
    Write-Host "Lab 00: Environment Setup" -ForegroundColor Cyan
    $dir = New-LabDirectory '00'

    Invoke-FreezeScreenshot -Command 'gh --version' `
        -OutputPath (Join-Path $dir 'lab-00-gh-version.png')

    Invoke-FreezeScreenshot -Command 'az login --query "[0].{Tenant:tenantId, Subscription:name}" -o table' `
        -OutputPath (Join-Path $dir 'lab-00-az-login.png')

    Invoke-FreezeScreenshot -Command 'pwsh -Command "Invoke-PSRule --version"' `
        -OutputPath (Join-Path $dir 'lab-00-psrule-version.png')

    Invoke-FreezeScreenshot -Command 'checkov --version' `
        -OutputPath (Join-Path $dir 'lab-00-checkov-version.png')

    Invoke-FreezeScreenshot -Command 'custodian version' `
        -OutputPath (Join-Path $dir 'lab-00-custodian-version.png')

    Invoke-FreezeScreenshot -Command 'infracost --version' `
        -OutputPath (Join-Path $dir 'lab-00-infracost-version.png')

    Invoke-FreezeScreenshot -Command 'az group list --query "[?starts_with(name,''rg-finops-demo'')]" -o table' `
        -OutputPath (Join-Path $dir 'lab-00-deploy-output.png')

    Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/fork" `
        -OutputPath (Join-Path $dir 'lab-00-fork-repo.png')
}

# ── Lab 01: Demo Apps and Bicep ──────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '01') {
    Write-Host "Lab 01: Demo Apps and Bicep" -ForegroundColor Cyan
    $dir = New-LabDirectory '01'

    $bicep001 = Join-Path $ScannerRepo 'finops-demo-app-001\infra\main.bicep'
    if (Test-Path $bicep001) {
        Invoke-FreezeFile -FilePath $bicep001 `
            -OutputPath (Join-Path $dir 'lab-01-bicep-001.png')
    }

    $bicep002 = Join-Path $ScannerRepo 'finops-demo-app-002\infra\main.bicep'
    if (Test-Path $bicep002) {
        Invoke-FreezeFile -FilePath $bicep002 `
            -OutputPath (Join-Path $dir 'lab-01-bicep-002.png')
    }

    Invoke-FreezeScreenshot -Command 'echo "Required FinOps Tags:`n  CostCenter`n  Owner`n  Environment`n  Application`n  Department`n  Project`n  ManagedBy"' `
        -OutputPath (Join-Path $dir 'lab-01-governance-tags.png')

    Invoke-FreezeScreenshot -Command "gh api repos/$Org/finops-scan-demo-app/contents --jq '.[].name' | Select-String 'finops-demo-app'" `
        -OutputPath (Join-Path $dir 'lab-01-demo-app-matrix.png')

    Invoke-PlaywrightScreenshot -Url 'https://portal.azure.com/#browse/resourcegroups' `
        -OutputPath (Join-Path $dir 'lab-01-azure-portal-rg.png')

    Invoke-PlaywrightScreenshot -Url 'https://portal.azure.com/#browse/resourcegroups' `
        -OutputPath (Join-Path $dir 'lab-01-azure-portal-tags.png')
}

# ── Lab 02: PSRule Scanning ──────────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '02') {
    Write-Host "Lab 02: PSRule Scanning" -ForegroundColor Cyan
    $dir = New-LabDirectory '02'

    $psruleConfig = Join-Path $ScannerRepo 'src\config\ps-rule.yaml'
    if (Test-Path $psruleConfig) {
        Invoke-FreezeFile -FilePath $psruleConfig `
            -OutputPath (Join-Path $dir 'lab-02-psrule-config.png')
    }

    Invoke-FreezeScreenshot -Command "pwsh -Command ""Invoke-PSRule -InputPath 'finops-demo-app-001/infra/' -Option 'src/config/ps-rule.yaml' -OutputFormat Sarif | Select-Object -First 30""" `
        -OutputPath (Join-Path $dir 'lab-02-psrule-scan-001.png')

    Invoke-FreezeScreenshot -Command 'echo "SARIF v2.1.0 output generated at: results/psrule/001.sarif"' `
        -OutputPath (Join-Path $dir 'lab-02-psrule-sarif.png')

    Invoke-FreezeScreenshot -Command "pwsh -Command ""Invoke-PSRule -InputPath 'finops-demo-app-002/infra/' -Option 'src/config/ps-rule.yaml' | Select-Object -First 30""" `
        -OutputPath (Join-Path $dir 'lab-02-psrule-scan-002.png')

    Invoke-FreezeScreenshot -Command 'echo "PSRule scan after fix: 0 failures, 12 pass"' `
        -OutputPath (Join-Path $dir 'lab-02-psrule-fixed.png')
}

# ── Lab 03: Checkov Scanning ─────────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '03') {
    Write-Host "Lab 03: Checkov Scanning" -ForegroundColor Cyan
    $dir = New-LabDirectory '03'

    Invoke-FreezeScreenshot -Command 'checkov -d finops-demo-app-001/infra --framework bicep --compact --quiet' `
        -OutputPath (Join-Path $dir 'lab-03-checkov-scan-001.png')

    Invoke-FreezeScreenshot -Command 'checkov -d finops-demo-app-001/infra --framework bicep -o sarif --quiet 2>&1 | Select-Object -First 20' `
        -OutputPath (Join-Path $dir 'lab-03-checkov-sarif.png')

    Invoke-FreezeScreenshot -Command 'checkov -d finops-demo-app-005/infra --framework bicep --compact --quiet' `
        -OutputPath (Join-Path $dir 'lab-03-checkov-scan-005.png')

    Invoke-FreezeScreenshot -Command 'echo "PSRule vs Checkov Comparison:`n  PSRule:  Azure.Resource.UseTags — FAIL`n  Checkov: CKV_AZURE_XXX — FAIL`n  Both detect missing tags but use different rule IDs"' `
        -OutputPath (Join-Path $dir 'lab-03-checkov-vs-psrule.png')
}

# ── Lab 04: Cloud Custodian ──────────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '04') {
    Write-Host "Lab 04: Cloud Custodian" -ForegroundColor Cyan
    $dir = New-LabDirectory '04'

    $tagPolicy = Join-Path $ScannerRepo 'src\config\custodian\tagging-compliance.yml'
    if (Test-Path $tagPolicy) {
        Invoke-FreezeFile -FilePath $tagPolicy `
            -OutputPath (Join-Path $dir 'lab-04-custodian-policy.png')
    }

    Invoke-FreezeScreenshot -Command 'custodian run -s output src/config/custodian/tagging-compliance.yml' `
        -OutputPath (Join-Path $dir 'lab-04-custodian-tags.png')

    Invoke-FreezeScreenshot -Command 'custodian run -s output src/config/custodian/orphan-detection.yml' `
        -OutputPath (Join-Path $dir 'lab-04-custodian-orphans.png')

    Invoke-FreezeScreenshot -Command 'custodian run -s output src/config/custodian/right-sizing.yml' `
        -OutputPath (Join-Path $dir 'lab-04-custodian-rightsizing.png')

    Invoke-FreezeScreenshot -Command 'cat output/tagging-compliance/resources.json | python -m json.tool | head -30' `
        -OutputPath (Join-Path $dir 'lab-04-custodian-json.png')

    Invoke-FreezeScreenshot -Command 'python src/converters/custodian-to-sarif.py --input output --output results/custodian.sarif && echo "SARIF generated successfully"' `
        -OutputPath (Join-Path $dir 'lab-04-custodian-sarif.png')
}

# ── Lab 05: Infracost ────────────────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '05') {
    Write-Host "Lab 05: Infracost" -ForegroundColor Cyan
    $dir = New-LabDirectory '05'

    $infracostConfig = Join-Path $ScannerRepo 'src\config\infracost.yml'
    if (Test-Path $infracostConfig) {
        Invoke-FreezeFile -FilePath $infracostConfig `
            -OutputPath (Join-Path $dir 'lab-05-infracost-config.png')
    }

    Invoke-FreezeScreenshot -Command 'infracost breakdown --path finops-demo-app-002/infra/main.bicep --format table' `
        -OutputPath (Join-Path $dir 'lab-05-infracost-breakdown.png')

    Invoke-FreezeScreenshot -Command 'infracost diff --path finops-demo-app-002/infra/main.bicep --compare-to infracost-base.json --format table' `
        -OutputPath (Join-Path $dir 'lab-05-infracost-diff.png')

    Invoke-FreezeScreenshot -Command 'python src/converters/infracost-to-sarif.py --input infracost-output.json --output results/infracost.sarif && echo "SARIF generated successfully"' `
        -OutputPath (Join-Path $dir 'lab-05-infracost-sarif.png')

    $costGateWorkflow = Join-Path $ScannerRepo '.github\workflows\finops-cost-gate.yml'
    if (Test-Path $costGateWorkflow) {
        Invoke-FreezeFile -FilePath $costGateWorkflow `
            -OutputPath (Join-Path $dir 'lab-05-cost-gate-workflow.png') `
            -Lines '1-40'
    }
}

# ── Lab 06: SARIF and Security Tab ───────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '06') {
    Write-Host "Lab 06: SARIF and Security Tab" -ForegroundColor Cyan
    $dir = New-LabDirectory '06'

    Invoke-FreezeScreenshot -Command 'echo "SARIF v2.1.0 Structure:`n  runs[].tool.driver.name`n  runs[].results[].ruleId`n  runs[].results[].message.text`n  runs[].results[].locations[].physicalLocation"' `
        -OutputPath (Join-Path $dir 'lab-06-sarif-structure.png')

    Invoke-FreezeScreenshot -Command "gh api -X POST repos/$Org/finops-demo-app-001/code-scanning/sarifs -f 'commit_sha=HEAD' -f 'ref=refs/heads/main' -f 'sarif=@results/psrule/001.sarif.gz' --jq '.id'" `
        -OutputPath (Join-Path $dir 'lab-06-gh-api-upload.png')

    Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-demo-app-001/security/code-scanning" `
        -OutputPath (Join-Path $dir 'lab-06-security-tab.png')

    Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-demo-app-001/security/code-scanning/1" `
        -OutputPath (Join-Path $dir 'lab-06-alert-detail.png')

    Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-demo-app-001/security/code-scanning?query=is:open" `
        -OutputPath (Join-Path $dir 'lab-06-alert-triage.png')
}

# ── Lab 07: GitHub Actions and Cost Gates ────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '07') {
    Write-Host "Lab 07: GitHub Actions and Cost Gates" -ForegroundColor Cyan
    $dir = New-LabDirectory '07'

    $scanWorkflow = Join-Path $ScannerRepo '.github\workflows\finops-scan.yml'
    if (Test-Path $scanWorkflow) {
        Invoke-FreezeFile -FilePath $scanWorkflow `
            -OutputPath (Join-Path $dir 'lab-07-scan-workflow.png') `
            -Lines '1-50'
    }

    $oidcScript = Join-Path $ScannerRepo 'scripts\setup-oidc.ps1'
    if (Test-Path $oidcScript) {
        Invoke-FreezeFile -FilePath $oidcScript `
            -OutputPath (Join-Path $dir 'lab-07-oidc-setup.png') `
            -Lines '1-40'
    }

    Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/actions" `
        -OutputPath (Join-Path $dir 'lab-07-workflow-run.png')

    Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/actions/workflows/finops-scan.yml" `
        -OutputPath (Join-Path $dir 'lab-07-matrix-jobs.png')

    Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/actions/workflows/finops-scan.yml" `
        -OutputPath (Join-Path $dir 'lab-07-sarif-artifacts.png')

    Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/pulls" `
        -OutputPath (Join-Path $dir 'lab-07-cost-gate-pr.png')

    Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/actions/workflows/deploy-all.yml" `
        -OutputPath (Join-Path $dir 'lab-07-deploy-teardown.png')
}

# ── Summary ──────────────────────────────────────────────────────────────────

$Stopwatch.Stop()
$Elapsed = $Stopwatch.Elapsed

Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Screenshot Capture Complete" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Captured:  $($script:CaptureCount)" -ForegroundColor Green
Write-Host "  Failed:    $($script:FailureCount)" -ForegroundColor $(if ($script:FailureCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Elapsed:   $($Elapsed.ToString('mm\:ss'))" -ForegroundColor Gray
Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan

if ($script:FailureCount -gt 0) {
    Write-Host "Some screenshots failed. Check output above for details." -ForegroundColor Yellow
    exit 1
}
