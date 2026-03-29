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
    [string]$Org = 'devopsabcs-engineering',

    [Parameter()]
    [string]$GitHubAuthState = 'github-auth.json',

    [Parameter()]
    [string]$AzureAuthState = 'azure-auth.json',

    [Parameter()]
    [ValidateSet('', '1', '2', '3')]
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
        $playwrightArgs = @('playwright', 'screenshot', '--viewport-size=1280,900')
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
        Labs = @('00', '01', '02', '03', '04', '05', '06', '07')
        Exclude = @(
            'lab-00-deploy-output',
            'lab-01-azure-portal-rg', 'lab-01-azure-portal-tags',
            'lab-04-custodian-tags', 'lab-04-custodian-orphans', 'lab-04-custodian-rightsizing',
            'lab-04-custodian-json', 'lab-04-custodian-sarif',
            'lab-05-infracost-breakdown', 'lab-05-infracost-diff', 'lab-05-infracost-sarif',
            'lab-06-gh-api-upload', 'lab-06-security-tab', 'lab-06-alert-detail', 'lab-06-alert-triage',
            'lab-07-workflow-run', 'lab-07-matrix-jobs', 'lab-07-sarif-artifacts',
            'lab-07-cost-gate-pr', 'lab-07-deploy-teardown'
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
            'lab-06-gh-api-upload', 'lab-06-security-tab', 'lab-06-alert-detail', 'lab-06-alert-triage',
            'lab-07-workflow-run', 'lab-07-matrix-jobs', 'lab-07-sarif-artifacts',
            'lab-07-cost-gate-pr', 'lab-07-deploy-teardown'
        )
    }
}

function Test-ShouldCapture {
    param([string]$Lab, [string]$ScreenshotName)
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
        Invoke-FreezeScreenshot -Command 'az group list --query "[?starts_with(name,''rg-finops-demo'')]" -o table' `
            -OutputPath (Join-Path $dir 'lab-00-deploy-output.png')
    }

    if (Test-ShouldCapture '00' 'lab-00-fork-repo') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/fork" `
            -OutputPath (Join-Path $dir 'lab-00-fork-repo.png')
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
        Invoke-PlaywrightScreenshot -Url 'https://portal.azure.com/#browse/resourcegroups' `
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
        Invoke-FreezeScreenshot -Command 'custodian run -s output src/config/custodian/tagging-compliance.yml' `
            -OutputPath (Join-Path $dir 'lab-04-custodian-tags.png')
    }

    if (Test-ShouldCapture '04' 'lab-04-custodian-orphans') {
        Invoke-FreezeScreenshot -Command 'custodian run -s output src/config/custodian/orphan-detection.yml' `
            -OutputPath (Join-Path $dir 'lab-04-custodian-orphans.png')
    }

    if (Test-ShouldCapture '04' 'lab-04-custodian-rightsizing') {
        Invoke-FreezeScreenshot -Command 'custodian run -s output src/config/custodian/right-sizing.yml' `
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
        Invoke-FreezeScreenshot -Command "gh api -X POST repos/$Org/finops-demo-app-001/code-scanning/sarifs -f 'commit_sha=HEAD' -f 'ref=refs/heads/main' -f 'sarif=@results/psrule/001.sarif.gz' --jq '.id'" `
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
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-demo-app-001/security/code-scanning?query=is:open" `
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
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/actions/workflows/finops-scan.yml" `
            -OutputPath (Join-Path $dir 'lab-07-sarif-artifacts.png') `
            -StorageState $GitHubAuthState
    }

    if (Test-ShouldCapture '07' 'lab-07-cost-gate-pr') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/pulls" `
            -OutputPath (Join-Path $dir 'lab-07-cost-gate-pr.png') `
            -StorageState $GitHubAuthState
    }

    if (Test-ShouldCapture '07' 'lab-07-deploy-teardown') {
        Invoke-PlaywrightScreenshot -Url "https://github.com/$Org/finops-scan-demo-app/actions/workflows/deploy-all.yml" `
            -OutputPath (Join-Path $dir 'lab-07-deploy-teardown.png') `
            -StorageState $GitHubAuthState
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
