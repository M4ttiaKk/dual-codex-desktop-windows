[CmdletBinding()]
param(
    [string]$Root = 'C:\CodexDual'
)

# Read-only health receipt for a later reboot or application-update check.
# It never starts or closes the app, reads credential contents, or inspects A.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reportDir = Join-Path $Root 'reports'
$profileRoot = Join-Path $Root 'profiles\B'
$codexHome = Join-Path $profileRoot 'codex-home'
$sqliteHome = Join-Path $codexHome 'sqlite'
$webData = Join-Path $profileRoot 'web-data'

if (-not (Test-Path -LiteralPath $Root)) { throw "Workspace mancante: $Root" }
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$report = Join-Path $reportDir ("Health-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')

function Write-Receipt {
    param([Parameter(Mandatory)][string]$Text)
    $Text | Tee-Object -FilePath $report -Append
}

$package = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { throw 'OpenAI.Codex non installato per l utente corrente.' }
$exe = Join-Path $package.InstallLocation 'app\ChatGPT.exe'

try {
    $bProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.CommandLine -and $_.CommandLine.IndexOf($webData, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
} catch {
    throw "Impossibile leggere i processi B (AccessDenied o errore CIM): $($_.Exception.Message)"
}

Write-Receipt 'Codex Dual Desktop - health receipt'
Write-Receipt "Timestamp: $(Get-Date -Format o)"
Write-Receipt "Package: $($package.PackageFullName)"
Write-Receipt "Version: $($package.Version)"
Write-Receipt "Executable exists: $(Test-Path -LiteralPath $exe)"
foreach ($path in @($profileRoot, $codexHome, $sqliteHome, $webData)) {
    Write-Receipt "Exists: $(Test-Path -LiteralPath $path) - $path"
}
Write-Receipt "Processes referencing B web-data: $($bProcesses.Count)"
foreach ($process in $bProcesses) {
    Write-Receipt "B PID: $($process.ProcessId); Parent: $($process.ParentProcessId)"
}
Write-Receipt 'Credential contents, auth.json, token values, profile A, and project contents were not read.'
Write-Receipt 'LIMIT: this receipt does not prove write isolation, account identity, project routing, or window visibility.'
Write-Receipt "RESULT: HEALTH_RECEIPT_CREATED - $report"
