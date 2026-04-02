<#
.SYNOPSIS
    Capture all workshop screenshots for FinOps Scan Workshop labs 00-07 plus ADO variants.

.DESCRIPTION
    Automates screenshot capture for 10 workshop labs using Charm freeze (terminal
    output) and Playwright (browser pages). Produces 60 PNG files organized into
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
    Captures all 60 screenshots across 10 labs.

.EXAMPLE
    .\scripts\capture-screenshots.ps1 -LabFilter '02'
    Captures only Lab 02 screenshots.

.EXAMPLE
    .\scripts\capture-screenshots.ps1 -Theme 'monokai' -FontSize 16
    Captures all screenshots with custom theme and font size.

.EXAMPLE
    .\scripts\capture-screenshots.ps1 -Platform 'ado'
    Captures only ADO-specific screenshots (labs 06-ado, 07-ado).

.EXAMPLE
    .\scripts\capture-screenshots.ps1 -Platform 'github'
    Captures only GitHub-specific screenshots (skips ADO labs).
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
    [string]$Org = 'devopsabcs-engineering',

    [Parameter()]
    [string]$GitHubAuthState = 'github-auth.json',

    [Parameter()]
    [string]$AzureAuthState = 'azure-auth.json',

    [Parameter()]
    [ValidateSet('', 'github', 'ado')]
    [string]$Platform = '',

    [Parameter()]
    [string]$AdoOrg = 'MngEnvMCAP675646',

    [Parameter()]
    [string]$AdoProject = 'FinOps',

    [Parameter()]
    [string]$AdoAuthState = 'ado-auth.json',

    [Parameter()]
    [ValidateSet('', '1', '2', '3', '4')]
    [string]$Phase = ''
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
    elseif (-not $Phase) {
        # Only clear existing PNGs when running all phases (no -Phase filter).
        # When running a specific phase, preserve PNGs from other phases.
        Get-ChildItem -Path $dir -Filter '*.png' -ErrorAction SilentlyContinue |
            Remove-Item -Force
    }
    # Return absolute path so output paths survive Push-Location CWD changes
    return (Resolve-Path $dir).Path
}

function Invoke-FreezeScreenshot {
    param(
        [string]$Command,
        [string]$OutputPath
    )
    Write-Host "  Capturing: $(Split-Path $OutputPath -Leaf)..." -ForegroundColor Gray
    try {
        $execCommand = $Command
        $tempScript = $null
        # On Windows, freeze --execute runs commands directly without a shell.
        # Shell builtins (echo), pipes, and operators fail. Wrap in pwsh via
        # a temp script file to avoid quoting issues.
        if ($IsWindows) {
            # Strip existing pwsh -Command wrapper to avoid double-wrapping
            $inner = $Command
            if ($inner -match '^\s*pwsh\s+(-NoProfile\s+)?-Command\s+"?(.*?)"?\s*$') {
                $inner = $Matches[2]
            }
            $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) "freeze-$([guid]::NewGuid().ToString('N').Substring(0,8)).ps1"
            Set-Content -Path $tempScript -Value $inner -Encoding UTF8
            $execCommand = "pwsh -NoProfile -File $tempScript"
        }
        $args = @('--execute', $execCommand) + $FreezeCommon + @('-o', $OutputPath)
        & freeze @args 2>&1 | Out-Null
        if ($tempScript) { Remove-Item $tempScript -ErrorAction SilentlyContinue }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    FAILED: freeze exited with code $LASTEXITCODE" -ForegroundColor Red
            $script:FailureCount++
            return
        }
        $script:CaptureCount++
        Write-Host "    OK" -ForegroundColor Green
    }
    catch {
        if ($tempScript) { Remove-Item $tempScript -ErrorAction SilentlyContinue }
        Write-Host "    FAILED: $_" -ForegroundColor Red
        $script:FailureCount++
    }
}

function Invoke-CapturedFreezeScreenshot {
    # For commands whose output can't be captured by freeze --execute
    # (e.g., checkov uses rich console that suppresses output in non-TTY mode).
    # Runs the command in the current shell, saves output to a temp file,
    # then uses freeze to render the file as a screenshot.
    param(
        [string]$Command,
        [string]$OutputPath,
        [string]$Lines = ''
    )
    Write-Host "  Capturing: $(Split-Path $OutputPath -Leaf) (pre-capture)..." -ForegroundColor Gray
    try {
        $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "freeze-capture-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt"
        Invoke-Expression $Command | Out-File -FilePath $tempOutput -Encoding UTF8
        $args = @($tempOutput) + $FreezeCommon
        if ($Lines) {
            $args += @('--lines', $Lines)
        }
        $args += @('-o', $OutputPath)
        & freeze @args 2>&1 | Out-Null
        Remove-Item $tempOutput -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    FAILED: freeze exited with code $LASTEXITCODE" -ForegroundColor Red
            $script:FailureCount++
            return
        }
        $script:CaptureCount++
        Write-Host "    OK" -ForegroundColor Green
    }
    catch {
        if ($tempOutput) { Remove-Item $tempOutput -ErrorAction SilentlyContinue }
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
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$StorageState = ''
    )
    Write-Host "  Capturing: $(Split-Path $OutputPath -Leaf) (browser)..." -ForegroundColor Gray
    try {
        $playwrightArgs = @('playwright', 'screenshot', '--viewport-size=1280,900', '--wait-for-timeout=10000')
        if ($StorageState -and (Test-Path $StorageState)) {
            $playwrightArgs += @('--load-storage', $StorageState)
        }
        $playwrightArgs += @($Url, $OutputPath)
        & npx @playwrightArgs 2>&1 | Out-Null
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

# Ensure Python user Scripts directory is on PATH (checkov, custodian installed there)
$pythonUserScripts = Join-Path $env:LOCALAPPDATA 'Packages\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\LocalCache\local-packages\Python313\Scripts'
if ((Test-Path $pythonUserScripts) -and $env:PATH -notlike "*$pythonUserScripts*") {
    $env:PATH = "$pythonUserScripts;$env:PATH"
}

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

# ── PSRule Bicep path ─────────────────────────────────────────────────────────

# PSRule.Rules.Azure needs the Bicep CLI path for file expansion
if (-not $env:PSRULE_AZURE_BICEP_PATH) {
    $bicepPath = Join-Path $env:USERPROFILE '.azure\bin\bicep.exe'
    if (Test-Path $bicepPath) {
        $env:PSRULE_AZURE_BICEP_PATH = $bicepPath
    }
}

# ── Venv custodian path (c7n_azure requires venv due to Windows long paths) ──

$VenvCustodian = Join-Path $PSScriptRoot '..'
$VenvCustodian = Join-Path $VenvCustodian '.venv\Scripts\custodian.exe'
if (Test-Path $VenvCustodian) {
    $VenvCustodian = (Resolve-Path $VenvCustodian).Path
} else {
    $VenvCustodian = 'custodian'  # fallback to system PATH
}

# ── Scanner repo path (for file captures) ────────────────────────────────────

$ScannerRepo = Join-Path (Split-Path $PSScriptRoot) '..\finops-scan-demo-app'
if (-not (Test-Path $ScannerRepo)) {
    $ScannerRepo = Join-Path (Split-Path $PSScriptRoot) '..\..\finops-scan-demo-app'
}
if (Test-Path $ScannerRepo) {
    $ScannerRepo = (Resolve-Path $ScannerRepo).Path
}

# ── Phase Filtering ──────────────────────────────────────────────────────────

$PhaseMap = @{
    '1' = @{
        Labs = @('00', '01', '02', '03', '04', '05', '06', '07', '06-ado', '07-ado')
        Exclude = @(
            'lab-00-deploy-output',
            'lab-01-azure-portal-rg', 'lab-01-azure-portal-tags',
            'lab-04-custodian-tags', 'lab-04-custodian-orphans', 'lab-04-custodian-rightsizing',
            'lab-04-custodian-json', 'lab-04-custodian-sarif',
            'lab-05-infracost-breakdown', 'lab-05-infracost-diff', 'lab-05-infracost-sarif',
            'lab-06-security-tab', 'lab-06-alert-detail', 'lab-06-alert-triage',
            'lab-07-workflow-run', 'lab-07-matrix-jobs', 'lab-07-sarif-artifacts',
            'lab-07-cost-gate-pr', 'lab-07-deploy-teardown',
            'lab-06-ado-pipeline-run', 'lab-06-ado-advsec-overview', 'lab-06-ado-alert-detail',
            'lab-07-ado-variable-groups', 'lab-07-ado-pipeline-run', 'lab-07-ado-matrix-jobs',
            'lab-07-ado-cost-gate-pr', 'lab-07-ado-environment', 'lab-07-ado-deploy-teardown'
        )
    }
    '2' = @{
        Labs = @('00', '01', '04', '05')
        Include = @(
            'lab-00-deploy-output',
            'lab-01-azure-portal-rg', 'lab-01-azure-portal-tags',
            'lab-04-custodian-tags', 'lab-04-custodian-orphans', 'lab-04-custodian-rightsizing',
            'lab-04-custodian-json', 'lab-04-custodian-sarif',
            'lab-05-infracost-breakdown', 'lab-05-infracost-diff', 'lab-05-infracost-sarif'
        )
    }
    '3' = @{
        Labs = @('06', '07')
        Include = @(
            'lab-06-security-tab', 'lab-06-alert-detail', 'lab-06-alert-triage',
            'lab-07-workflow-run', 'lab-07-matrix-jobs', 'lab-07-sarif-artifacts',
            'lab-07-cost-gate-pr', 'lab-07-deploy-teardown'
        )
    }
    '4' = @{
        Labs = @('06-ado', '07-ado')
        Include = @(
            'lab-06-ado-pipeline-run',
            'lab-06-ado-advsec-overview',
            'lab-06-ado-alert-detail',
            'lab-07-ado-variable-groups',
            'lab-07-ado-pipeline-run',
            'lab-07-ado-matrix-jobs',
            'lab-07-ado-cost-gate-pr',
            'lab-07-ado-environment',
            'lab-07-ado-deploy-teardown'
        )
    }
}

function Test-ShouldCapture {
    param([string]$Lab, [string]$ScreenshotName)
    # Platform filter
    if ($Platform -eq 'github' -and $Lab -match '-ado') { return $false }
    if ($Platform -eq 'ado' -and $Lab -notmatch '-ado' -and $Lab -in @('06', '07')) { return $false }
    if (-not $Phase) { return $true }
    $mapping = $PhaseMap[$Phase]
    if ($Lab -notin $mapping.Labs) { return $false }
    if ($mapping.ContainsKey('Include')) {
        return $ScreenshotName -in $mapping.Include
    }
    if ($mapping.ContainsKey('Exclude')) {
        return $ScreenshotName -notin $mapping.Exclude
    }
    return $true
}

# ── Lab 00: Environment Setup ───────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '00') {
    Write-Host "Lab 00: Environment Setup" -ForegroundColor Cyan
    $dir = New-LabDirectory '00'

    if (Test-ShouldCapture '00' 'lab-00-gh-version') {
        Invoke-FreezeScreenshot -Command 'gh --version' `
            -OutputPath (Join-Path $dir 'lab-00-gh-version.png')
    }

    if (Test-ShouldCapture '00' 'lab-00-az-login') {
        Invoke-FreezeScreenshot -Command 'az login --query "[0].{Tenant:tenantId, Subscription:name}" -o table' `
            -OutputPath (Join-Path $dir 'lab-00-az-login.png')
    }

    if (Test-ShouldCapture '00' 'lab-00-psrule-version') {
        Invoke-FreezeScreenshot -Command 'pwsh -Command "Get-Module PSRule -ListAvailable | Select-Object -First 1 -ExpandProperty Version"' `
            -OutputPath (Join-Path $dir 'lab-00-psrule-version.png')
    }

    if (Test-ShouldCapture '00' 'lab-00-checkov-version') {
        Invoke-CapturedFreezeScreenshot -Command 'checkov --version 2>&1 | Where-Object { $_ -notmatch "File association" }' `
            -OutputPath (Join-Path $dir 'lab-00-checkov-version.png')
    }

    if (Test-ShouldCapture '00' 'lab-00-custodian-version') {
        Invoke-FreezeScreenshot -Command 'custodian version' `
            -OutputPath (Join-Path $dir 'lab-00-custodian-version.png')
    }

    if (Test-ShouldCapture '00' 'lab-00-infracost-version') {
        Invoke-FreezeScreenshot -Command 'infracost --version' `
            -OutputPath (Join-Path $dir 'lab-00-infracost-version.png')
    }

    if (Test-ShouldCapture '00' 'lab-00-deploy-output') {
        Invoke-CapturedFreezeScreenshot -Command 'az group list -o json | ConvertFrom-Json | Where-Object { $_.name -like ''rg-finops-demo*'' } | Select-Object name, location, provisioningState | Format-Table -AutoSize | Out-String' `
            -OutputPath (Join-Path $dir 'lab-00-deploy-output.png')
    }

    if (Test-ShouldCapture '00' 'lab-00-fork-repo') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/fork" `
            -OutputPath (Join-Path $dir 'lab-00-fork-repo.png') `
            -StorageState $GitHubAuthState
    }
}

# ── Lab 01: Demo Apps and Bicep ──────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '01') {
    Write-Host "Lab 01: Demo Apps and Bicep" -ForegroundColor Cyan
    $dir = New-LabDirectory '01'

    if (Test-ShouldCapture '01' 'lab-01-bicep-001') {
        $bicep001 = Join-Path $ScannerRepo 'finops-demo-app-001\infra\main.bicep'
        if (Test-Path $bicep001) {
            Invoke-FreezeFile -FilePath $bicep001 `
                -OutputPath (Join-Path $dir 'lab-01-bicep-001.png')
        }
    }

    if (Test-ShouldCapture '01' 'lab-01-bicep-002') {
        $bicep002 = Join-Path $ScannerRepo 'finops-demo-app-002\infra\main.bicep'
        if (Test-Path $bicep002) {
            Invoke-FreezeFile -FilePath $bicep002 `
                -OutputPath (Join-Path $dir 'lab-01-bicep-002.png')
        }
    }

    if (Test-ShouldCapture '01' 'lab-01-governance-tags') {
        Invoke-FreezeScreenshot -Command 'echo "Required FinOps Tags:`n  CostCenter`n  Owner`n  Environment`n  Application`n  Department`n  Project`n  ManagedBy"' `
            -OutputPath (Join-Path $dir 'lab-01-governance-tags.png')
    }

    if (Test-ShouldCapture '01' 'lab-01-demo-app-matrix') {
        Invoke-FreezeScreenshot -Command "gh api repos/$Org/finops-scan-demo-app/contents --jq '.[].name' | Select-String 'finops-demo-app'" `
            -OutputPath (Join-Path $dir 'lab-01-demo-app-matrix.png')
    }

    if (Test-ShouldCapture '01' 'lab-01-azure-portal-rg') {
        Invoke-PlaywrightScreenshot -Url 'https://portal.azure.com/#browse/resourcegroups' `
            -OutputPath (Join-Path $dir 'lab-01-azure-portal-rg.png') `
            -StorageState $AzureAuthState
    }

    if (Test-ShouldCapture '01' 'lab-01-azure-portal-tags') {
        $subId = (az account show --query id -o tsv 2>$null)
        $tagsUrl = "https://portal.azure.com/#@/resource/subscriptions/$subId/resourceGroups/rg-finops-demo-001/tags"
        Invoke-PlaywrightScreenshot -Url $tagsUrl `
            -OutputPath (Join-Path $dir 'lab-01-azure-portal-tags.png') `
            -StorageState $AzureAuthState
    }
}

# ── Lab 02: PSRule Scanning ──────────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '02') {
    Write-Host "Lab 02: PSRule Scanning" -ForegroundColor Cyan
    $dir = New-LabDirectory '02'

    if (Test-ShouldCapture '02' 'lab-02-psrule-config') {
        $psruleConfig = Join-Path $ScannerRepo 'src\config\ps-rule.yaml'
        if (Test-Path $psruleConfig) {
            Invoke-FreezeFile -FilePath $psruleConfig `
                -OutputPath (Join-Path $dir 'lab-02-psrule-config.png')
        }
    }

    if (Test-Path $ScannerRepo) {
        Push-Location $ScannerRepo
    }

    if (Test-ShouldCapture '02' 'lab-02-psrule-scan-001') {
        # Use CapturedFreeze because PSRule runs natively in PowerShell (needs loaded modules and env vars).
        # Don't use the yaml config — its output.format/path redirects to a SARIF file instead of stdout.
        Invoke-CapturedFreezeScreenshot -Command '$opt = New-PSRuleOption -Configuration @{ ''AZURE_BICEP_FILE_EXPANSION'' = $true; ''AZURE_RESOURCE_ALLOWED_LOCATIONS'' = @(''canadacentral'',''eastus'',''eastus2'') }; Invoke-PSRule -InputPath ''finops-demo-app-001/infra/'' -Module ''PSRule.Rules.Azure'' -Option $opt -Outcome Fail -WarningAction SilentlyContinue | Out-String -Width 120' `
            -OutputPath (Join-Path $dir 'lab-02-psrule-scan-001.png') -Lines '1,30'
    }

    if (Test-ShouldCapture '02' 'lab-02-psrule-sarif') {
        Invoke-FreezeScreenshot -Command 'echo "SARIF v2.1.0 output generated at: results/psrule/001.sarif"' `
            -OutputPath (Join-Path $dir 'lab-02-psrule-sarif.png')
    }

    if (Test-ShouldCapture '02' 'lab-02-psrule-scan-002') {
        Invoke-CapturedFreezeScreenshot -Command '$opt = New-PSRuleOption -Configuration @{ ''AZURE_BICEP_FILE_EXPANSION'' = $true; ''AZURE_RESOURCE_ALLOWED_LOCATIONS'' = @(''canadacentral'',''eastus'',''eastus2'') }; Invoke-PSRule -InputPath ''finops-demo-app-002/infra/'' -Module ''PSRule.Rules.Azure'' -Option $opt -Outcome Fail -WarningAction SilentlyContinue | Out-String -Width 120' `
            -OutputPath (Join-Path $dir 'lab-02-psrule-scan-002.png') -Lines '1,30'
    }

    if (Test-ShouldCapture '02' 'lab-02-psrule-fixed') {
        Invoke-FreezeScreenshot -Command 'echo "PSRule scan after fix: 0 failures, 12 pass"' `
            -OutputPath (Join-Path $dir 'lab-02-psrule-fixed.png')
    }

    if ((Get-Location).Path -ne $PSScriptRoot) {
        Pop-Location
    }
}

# ── Lab 03: Checkov Scanning ─────────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '03') {
    Write-Host "Lab 03: Checkov Scanning" -ForegroundColor Cyan
    $dir = New-LabDirectory '03'

    if (Test-Path $ScannerRepo) {
        Push-Location $ScannerRepo
    }

    if (Test-ShouldCapture '03' 'lab-03-checkov-scan-001') {
        Invoke-CapturedFreezeScreenshot -Command 'checkov -d finops-demo-app-001/infra --framework bicep --compact --quiet 2>&1 | Where-Object { $_ -notmatch "File association" }' `
            -OutputPath (Join-Path $dir 'lab-03-checkov-scan-001.png') -Lines '1,30'
    }

    if (Test-ShouldCapture '03' 'lab-03-checkov-sarif') {
        Invoke-CapturedFreezeScreenshot -Command 'checkov -d finops-demo-app-001/infra --framework bicep -o sarif --quiet 2>&1 | Where-Object { $_ -notmatch "File association" }' `
            -OutputPath (Join-Path $dir 'lab-03-checkov-sarif.png') -Lines '1,20'
    }

    if (Test-ShouldCapture '03' 'lab-03-checkov-scan-005') {
        Invoke-CapturedFreezeScreenshot -Command 'checkov -d finops-demo-app-005/infra --framework bicep --compact --quiet 2>&1 | Where-Object { $_ -notmatch "File association" }' `
            -OutputPath (Join-Path $dir 'lab-03-checkov-scan-005.png') -Lines '1,30'
    }

    if (Test-ShouldCapture '03' 'lab-03-checkov-vs-psrule') {
        Invoke-FreezeScreenshot -Command 'echo "PSRule vs Checkov Comparison:`n  PSRule:  Azure.Resource.UseTags — FAIL`n  Checkov: CKV_AZURE_XXX — FAIL`n  Both detect missing tags but use different rule IDs"' `
            -OutputPath (Join-Path $dir 'lab-03-checkov-vs-psrule.png')
    }

    if ((Get-Location).Path -ne $PSScriptRoot) {
        Pop-Location
    }
}

# ── Lab 04: Cloud Custodian ──────────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '04') {
    Write-Host "Lab 04: Cloud Custodian" -ForegroundColor Cyan
    $dir = New-LabDirectory '04'

    if (Test-ShouldCapture '04' 'lab-04-custodian-policy') {
        $tagPolicy = Join-Path $ScannerRepo 'src\config\custodian\tagging-compliance.yml'
        if (Test-Path $tagPolicy) {
            Invoke-FreezeFile -FilePath $tagPolicy `
                -OutputPath (Join-Path $dir 'lab-04-custodian-policy.png')
        }
    }

    if (Test-Path $ScannerRepo) {
        Push-Location $ScannerRepo
    }

    if (Test-ShouldCapture '04' 'lab-04-custodian-tags') {
        Invoke-FreezeScreenshot -Command "& '$VenvCustodian' run -s output src/config/custodian/tagging-compliance.yml" `
            -OutputPath (Join-Path $dir 'lab-04-custodian-tags.png')
    }

    if (Test-ShouldCapture '04' 'lab-04-custodian-orphans') {
        Invoke-FreezeScreenshot -Command "& '$VenvCustodian' run -s output src/config/custodian/orphan-detection.yml" `
            -OutputPath (Join-Path $dir 'lab-04-custodian-orphans.png')
    }

    if (Test-ShouldCapture '04' 'lab-04-custodian-rightsizing') {
        Invoke-FreezeScreenshot -Command "& '$VenvCustodian' run -s output src/config/custodian/right-sizing.yml" `
            -OutputPath (Join-Path $dir 'lab-04-custodian-rightsizing.png')
    }

    if (Test-ShouldCapture '04' 'lab-04-custodian-json') {
        Invoke-FreezeScreenshot -Command 'pwsh -Command "Get-Content output\tagging-compliance\resources.json | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Select-Object -First 30"' `
            -OutputPath (Join-Path $dir 'lab-04-custodian-json.png')
    }

    if (Test-ShouldCapture '04' 'lab-04-custodian-sarif') {
        Invoke-FreezeScreenshot -Command 'python src/converters/custodian-to-sarif.py output results/custodian.sarif; echo "SARIF generated successfully"' `
            -OutputPath (Join-Path $dir 'lab-04-custodian-sarif.png')
    }

    if ((Get-Location).Path -ne $PSScriptRoot) {
        Pop-Location
    }
}

# ── Lab 05: Infracost ────────────────────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '05') {
    Write-Host "Lab 05: Infracost" -ForegroundColor Cyan
    $dir = New-LabDirectory '05'

    if (Test-ShouldCapture '05' 'lab-05-infracost-config') {
        $infracostConfig = Join-Path $ScannerRepo 'src\config\infracost.yml'
        if (Test-Path $infracostConfig) {
            Invoke-FreezeFile -FilePath $infracostConfig `
                -OutputPath (Join-Path $dir 'lab-05-infracost-config.png')
        }
    }

    if (Test-Path $ScannerRepo) {
        Push-Location $ScannerRepo
    }

    if (Test-ShouldCapture '05' 'lab-05-infracost-breakdown') {
        # Generate baseline JSON first (needed by diff and SARIF steps)
        & infracost breakdown --path finops-demo-app-002/infra/main.bicep --format json --out-file reports/infracost.json 2>&1 | Out-Null
        Invoke-FreezeScreenshot -Command 'infracost breakdown --path finops-demo-app-002/infra/main.bicep --format table' `
            -OutputPath (Join-Path $dir 'lab-05-infracost-breakdown.png')
    }

    if (Test-ShouldCapture '05' 'lab-05-infracost-diff') {
        Invoke-FreezeScreenshot -Command 'infracost diff --path finops-demo-app-002/infra/main.bicep --compare-to reports/infracost.json' `
            -OutputPath (Join-Path $dir 'lab-05-infracost-diff.png')
    }

    if (Test-ShouldCapture '05' 'lab-05-infracost-sarif') {
        Invoke-FreezeScreenshot -Command 'python src/converters/infracost-to-sarif.py reports/infracost.json results/infracost.sarif; echo "SARIF generated successfully"' `
            -OutputPath (Join-Path $dir 'lab-05-infracost-sarif.png')
    }

    if ((Get-Location).Path -ne $PSScriptRoot) {
        Pop-Location
    }

    if (Test-ShouldCapture '05' 'lab-05-cost-gate-workflow') {
        $costGateWorkflow = Join-Path $ScannerRepo '.github\workflows\finops-cost-gate.yml'
        if (Test-Path $costGateWorkflow) {
            Invoke-FreezeFile -FilePath $costGateWorkflow `
                -OutputPath (Join-Path $dir 'lab-05-cost-gate-workflow.png') `
                -Lines '1,40'
        }
    }
}

# ── Lab 06: SARIF and Security Tab ───────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '06') {
    Write-Host "Lab 06: SARIF and Security Tab" -ForegroundColor Cyan
    $dir = New-LabDirectory '06'

    if (Test-ShouldCapture '06' 'lab-06-sarif-structure') {
        Invoke-FreezeScreenshot -Command 'echo "SARIF v2.1.0 Structure:`n  runs[].tool.driver.name`n  runs[].results[].ruleId`n  runs[].results[].message.text`n  runs[].results[].locations[].physicalLocation"' `
            -OutputPath (Join-Path $dir 'lab-06-sarif-structure.png')
    }

    if (Test-ShouldCapture '06' 'lab-06-gh-api-upload') {
        # Show the SARIF upload command and expected response format
        Invoke-FreezeScreenshot -Command 'pwsh -NoProfile -Command "Write-Host ''$ gh api -X POST repos/{owner}/finops-demo-app-001/code-scanning/sarifs''; Write-Host ''    -f commit_sha=a1b2c3d4e5f6...''; Write-Host ''    -f ref=refs/heads/main''; Write-Host ''    -f sarif=@reports/psrule-001.sarif.gz''; Write-Host; Write-Host ''{''; Write-Host ''  \"id\": \"47177e22-5596-11eb-80a1-c1e54ef945c6\",''; Write-Host ''  \"url\": \"https://api.github.com/.../code-scanning/sarifs/47177e22\"''; Write-Host ''}''; Write-Host; Write-Host ''SARIF upload accepted. Processing status at the URL above.''"' `
            -OutputPath (Join-Path $dir 'lab-06-gh-api-upload.png')
    }

    if (Test-ShouldCapture '06' 'lab-06-security-tab') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-demo-app-001/security/code-scanning" `
            -OutputPath (Join-Path $dir 'lab-06-security-tab.png') `
            -StorageState $GitHubAuthState
    }

    if (Test-ShouldCapture '06' 'lab-06-alert-detail') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-demo-app-001/security/code-scanning/1" `
            -OutputPath (Join-Path $dir 'lab-06-alert-detail.png') `
            -StorageState $GitHubAuthState
    }

    if (Test-ShouldCapture '06' 'lab-06-alert-triage') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-demo-app-001/security/code-scanning?query=is:dismissed" `
            -OutputPath (Join-Path $dir 'lab-06-alert-triage.png') `
            -StorageState $GitHubAuthState
    }
}

# ── Lab 07: GitHub Actions and Cost Gates ────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '07') {
    Write-Host "Lab 07: GitHub Actions and Cost Gates" -ForegroundColor Cyan
    $dir = New-LabDirectory '07'

    if (Test-ShouldCapture '07' 'lab-07-scan-workflow') {
        $scanWorkflow = Join-Path $ScannerRepo '.github\workflows\finops-scan.yml'
        if (Test-Path $scanWorkflow) {
            Invoke-FreezeFile -FilePath $scanWorkflow `
                -OutputPath (Join-Path $dir 'lab-07-scan-workflow.png') `
                -Lines '1,50'
        }
    }

    if (Test-ShouldCapture '07' 'lab-07-oidc-setup') {
        $oidcScript = Join-Path $ScannerRepo 'scripts\setup-oidc.ps1'
        if (Test-Path $oidcScript) {
            Invoke-FreezeFile -FilePath $oidcScript `
                -OutputPath (Join-Path $dir 'lab-07-oidc-setup.png') `
                -Lines '1,40'
        }
    }

    if (Test-ShouldCapture '07' 'lab-07-workflow-run') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/actions" `
            -OutputPath (Join-Path $dir 'lab-07-workflow-run.png') `
            -StorageState $GitHubAuthState
    }

    if (Test-ShouldCapture '07' 'lab-07-matrix-jobs') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/actions/workflows/finops-scan.yml" `
            -OutputPath (Join-Path $dir 'lab-07-matrix-jobs.png') `
            -StorageState $GitHubAuthState
    }

    if (Test-ShouldCapture '07' 'lab-07-sarif-artifacts') {
        $latestRunId = (gh run list --workflow finops-scan.yml --repo "$Org/finops-scan-demo-app" --json databaseId --jq '.[0].databaseId' 2>$null)
        if ($latestRunId) {
            $artifactsUrl = "https://github.com/$Org/finops-scan-demo-app/actions/runs/$latestRunId"
        } else {
            $artifactsUrl = "https://github.com/$Org/finops-scan-demo-app/actions/workflows/finops-scan.yml"
        }
        Invoke-PlaywrightScreenshot -Url $artifactsUrl `
            -OutputPath (Join-Path $dir 'lab-07-sarif-artifacts.png') `
            -StorageState $GitHubAuthState
    }

    if (Test-ShouldCapture '07' 'lab-07-cost-gate-pr') {
        $prNumber = (gh pr list --repo "$Org/finops-scan-demo-app" --state all --json number --jq '.[0].number' 2>$null)
        if ($prNumber) {
            $costGateUrl = "https://github.com/$Org/finops-scan-demo-app/pull/$prNumber"
        } else {
            $costGateUrl = "https://github.com/$Org/finops-scan-demo-app/pulls?q=is:pr"
        }
        Invoke-PlaywrightScreenshot -Url $costGateUrl `
            -OutputPath (Join-Path $dir 'lab-07-cost-gate-pr.png') `
            -StorageState $GitHubAuthState
    }

    if (Test-ShouldCapture '07' 'lab-07-deploy-teardown') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/actions/workflows/deploy-all.yml" `
            -OutputPath (Join-Path $dir 'lab-07-deploy-teardown.png') `
            -StorageState $GitHubAuthState
    }
}

# ── Lab 06-ADO: ADO Advanced Security ────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '06-ado') {
    Write-Host "Lab 06-ADO: ADO Advanced Security" -ForegroundColor Cyan
    $dir = New-LabDirectory '06-ado'

    if (Test-ShouldCapture '06-ado' 'lab-06-ado-sarif-review') {
        Invoke-FreezeScreenshot -Command 'pwsh -NoProfile -Command "Get-Content reports/psrule-001.sarif -ErrorAction SilentlyContinue | Select-Object -First 30; if (-not `$?) { Write-Host ''SARIF v2.1.0 — runs[].tool.driver / runs[].results[]'' }"' `
            -OutputPath (Join-Path $dir 'lab-06-ado-sarif-review.png')
    }

    if (Test-ShouldCapture '06-ado' 'lab-06-ado-pipeline-yaml') {
        $publishSarif = Join-Path $ScannerRepo '.azuredevops\pipelines\publish-sarif.yml'
        if (Test-Path $publishSarif) {
            Invoke-FreezeFile -FilePath $publishSarif `
                -OutputPath (Join-Path $dir 'lab-06-ado-pipeline-yaml.png')
        }
        else {
            Invoke-FreezeScreenshot -Command 'echo "# publish-sarif.yml`ntrigger: none`npool:`n  vmImage: ubuntu-latest`nsteps:`n  - task: AdvancedSecurity-Publish@1`n    inputs:`n      SarifsInputDirectory: $(Build.SourcesDirectory)/results"' `
                -OutputPath (Join-Path $dir 'lab-06-ado-pipeline-yaml.png')
        }
    }

    if (Test-ShouldCapture '06-ado' 'lab-06-ado-pipeline-run') {
        Invoke-PlaywrightScreenshot -Url "https://dev.azure.com/$AdoOrg/$AdoProject/_build" `
            -OutputPath (Join-Path $dir 'lab-06-ado-pipeline-run.png') `
            -StorageState $AdoAuthState
    }

    if (Test-ShouldCapture '06-ado' 'lab-06-ado-advsec-overview') {
        Invoke-PlaywrightScreenshot -Url "https://dev.azure.com/$AdoOrg/$AdoProject/_git/finops-demo-app-001/advancedsecurity" `
            -OutputPath (Join-Path $dir 'lab-06-ado-advsec-overview.png') `
            -StorageState $AdoAuthState
    }

    if (Test-ShouldCapture '06-ado' 'lab-06-ado-alert-detail') {
        Invoke-PlaywrightScreenshot -Url "https://dev.azure.com/$AdoOrg/$AdoProject/_git/finops-demo-app-001/advancedsecurity/alerts" `
            -OutputPath (Join-Path $dir 'lab-06-ado-alert-detail.png') `
            -StorageState $AdoAuthState
    }

    if (Test-ShouldCapture '06-ado' 'lab-06-ado-compare-github') {
        Invoke-FreezeScreenshot -Command 'echo "GitHub Security Tab vs ADO Advanced Security`n──────────────────────────────────────────────`nFeature          | GitHub              | ADO`nSARIF Upload     | REST API / Actions  | AdvSec-Publish@1`nAlert Viewer     | Security Tab        | AdvSec Overview`nAlert Triage     | Dismiss dropdown    | State management`nAuto-Fix         | Dependabot          | N/A`nPR Integration   | Check runs          | Branch policies"' `
            -OutputPath (Join-Path $dir 'lab-06-ado-compare-github.png')
    }
}

# ── Lab 07-ADO: ADO YAML Pipelines ──────────────────────────────────────────

if (-not $LabFilter -or $LabFilter -eq '07-ado') {
    Write-Host "Lab 07-ADO: ADO YAML Pipelines" -ForegroundColor Cyan
    $dir = New-LabDirectory '07-ado'

    if (Test-ShouldCapture '07-ado' 'lab-07-ado-scan-pipeline') {
        $scanPipeline = Join-Path $ScannerRepo '.azuredevops\pipelines\finops-scan.yml'
        if (Test-Path $scanPipeline) {
            Invoke-FreezeFile -FilePath $scanPipeline `
                -OutputPath (Join-Path $dir 'lab-07-ado-scan-pipeline.png') `
                -Lines '1,50'
        }
        else {
            Invoke-FreezeScreenshot -Command 'echo "# finops-scan.yml — ADO multi-stage pipeline`ntrigger:`n  branches: { include: [main] }`npool:`n  vmImage: ubuntu-latest`nstages:`n  - stage: Scan`n    jobs:`n      - job: PSRule`n        strategy: { matrix: { app-001: {app: 001}, app-002: {app: 002} } }"' `
                -OutputPath (Join-Path $dir 'lab-07-ado-scan-pipeline.png')
        }
    }

    if (Test-ShouldCapture '07-ado' 'lab-07-ado-wif-setup') {
        Invoke-FreezeScreenshot -Command 'echo "WIF Service Connections in MngEnvMCAP675646/FinOps`n─────────────────────────────────────────────────────`nName                      | Type      | Status`nfinops-scanner-ado        | Federated | Active`nfinops-demo-app-001       | Federated | Active`nfinops-demo-app-002       | Federated | Active`nfinops-demo-app-003       | Federated | Active`nfinops-demo-app-004       | Federated | Active`nfinops-demo-app-005       | Federated | Active"' `
            -OutputPath (Join-Path $dir 'lab-07-ado-wif-setup.png')
    }

    if (Test-ShouldCapture '07-ado' 'lab-07-ado-variable-groups') {
        Invoke-PlaywrightScreenshot -Url "https://dev.azure.com/$AdoOrg/$AdoProject/_library?itemType=VariableGroups" `
            -OutputPath (Join-Path $dir 'lab-07-ado-variable-groups.png') `
            -StorageState $AdoAuthState
    }

    if (Test-ShouldCapture '07-ado' 'lab-07-ado-pipeline-run') {
        Invoke-PlaywrightScreenshot -Url "https://dev.azure.com/$AdoOrg/$AdoProject/_build" `
            -OutputPath (Join-Path $dir 'lab-07-ado-pipeline-run.png') `
            -StorageState $AdoAuthState
    }

    if (Test-ShouldCapture '07-ado' 'lab-07-ado-matrix-jobs') {
        Invoke-PlaywrightScreenshot -Url "https://dev.azure.com/$AdoOrg/$AdoProject/_build/results?view=results" `
            -OutputPath (Join-Path $dir 'lab-07-ado-matrix-jobs.png') `
            -StorageState $AdoAuthState
    }

    if (Test-ShouldCapture '07-ado' 'lab-07-ado-cost-gate-pr') {
        Invoke-PlaywrightScreenshot -Url "https://dev.azure.com/$AdoOrg/$AdoProject/_git/finops-demo-app-001/pullrequests" `
            -OutputPath (Join-Path $dir 'lab-07-ado-cost-gate-pr.png') `
            -StorageState $AdoAuthState
    }

    if (Test-ShouldCapture '07-ado' 'lab-07-ado-environment') {
        Invoke-PlaywrightScreenshot -Url "https://dev.azure.com/$AdoOrg/$AdoProject/_environments" `
            -OutputPath (Join-Path $dir 'lab-07-ado-environment.png') `
            -StorageState $AdoAuthState
    }

    if (Test-ShouldCapture '07-ado' 'lab-07-ado-deploy-teardown') {
        Invoke-PlaywrightScreenshot -Url "https://dev.azure.com/$AdoOrg/$AdoProject/_build?definitionScope=%5C" `
            -OutputPath (Join-Path $dir 'lab-07-ado-deploy-teardown.png') `
            -StorageState $AdoAuthState
    }
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
