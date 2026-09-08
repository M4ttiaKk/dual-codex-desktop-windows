[CmdletBinding()]
param(
    [ValidateSet('Prepare', 'QualifyB', 'VerifyBStopped', 'RestoreBWindow', 'Coexistence')]
    [string]$Mode = 'Prepare',
    [string]$Root = 'C:\CodexDual',
    [switch]$NoWait
)

# This script never reads credential contents or starts a login flow.
# QualifyB is anonymous and requires A to be closed. Coexistence is a later,
# separately authorized observational check and must not be used before QualifyB passes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reportDir = Join-Path $Root 'reports'
$profileRoot = Join-Path $Root 'profiles\B'
$codexHome = Join-Path $profileRoot 'codex-home'
$sqliteHome = Join-Path $codexHome 'sqlite'
$webData = Join-Path $profileRoot 'web-data'
$marker = Join-Path $profileRoot 'PHASE1-PREPARED.txt'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $reportDir "Phase1-$Mode-$timestamp.txt"

function Write-Report {
    param([Parameter(Mandatory)][string]$Text)
    $Text | Tee-Object -FilePath $report -Append
}

function Stop-WithReport {
    param([Parameter(Mandatory)][string]$Text)
    Write-Report "RESULT: STOP - $Text"
    throw $Text
}

function Get-TargetPackage {
    $package = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $package) { throw 'OpenAI.Codex is not installed for the current user.' }
    $exe = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw "ChatGPT.exe non trovato: $exe" }
    return [pscustomobject]@{ Package = $package; Executable = $exe }
}

function Get-NamedDesktopProcesses {
    # Current installed package launches ChatGPT.exe. Do not treat a generic
    # `codex` helper as proof that the graphical A instance remains open.
    @(Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue)
}

function Get-BProcesses {
    param([Parameter(Mandatory)][string]$BWebData)
    try {
        @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.CommandLine -and $_.CommandLine.IndexOf($BWebData, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    } catch {
        throw "Impossibile leggere i processi B (AccessDenied o errore CIM): $($_.Exception.Message)"
    }
}

if ($Root.Contains('"')) { throw 'The workspace path must not contain a double quote.' }
if (-not (Test-Path -LiteralPath $Root)) { throw "Workspace assente: $Root" }
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
Write-Report "Codex Dual Desktop - $Mode"
Write-Report "Timestamp: $(Get-Date -Format o)"
Write-Report "Root: $Root"

$target = Get-TargetPackage
Write-Report "Package: $($target.Package.PackageFullName)"
Write-Report "Version: $($target.Package.Version)"
Write-Report "Executable: $($target.Executable)"
Write-Report 'Credential contents, auth.json, tokens, repositories, and profile A are not read.'

if ($Mode -eq 'Prepare') {
    $existingBData = @(
        @($codexHome, $sqliteHome, $webData, $marker) | Where-Object {
            Test-Path -LiteralPath $_
        }
    )
    if ($existingBData.Count -gt 0) {
        Stop-WithReport "B data already exists: $($existingBData -join ', '). No B write was performed."
    }

    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

    foreach ($path in @($codexHome, $sqliteHome, $webData)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Report "Created: $path"
    }
    $config = 'cli_auth_credentials_store = "file"' + "`r`n" + 'mcp_oauth_credentials_store = "file"' + "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $codexHome 'config.toml'), $config, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($marker, "Prepared without launch or login.`r`n", [System.Text.UTF8Encoding]::new($false))
    Write-Report 'RESULT: PREPARE_PASS'
    Write-Report 'LIMIT: no application was started; no isolation claim is established.'
    exit 0
}

if (-not (Test-Path -LiteralPath $marker)) { Stop-WithReport 'Profilo B non preparato. Eseguire prima -Mode Prepare.' }

if ($Mode -eq 'VerifyBStopped') {
    $stillRunning = @(Get-BProcesses -BWebData $webData)
    Write-Report "Processes referencing B web-data: $($stillRunning.Count)"
    foreach ($process in $stillRunning) {
        Write-Report "B PID: $($process.ProcessId); Parent: $($process.ParentProcessId)"
    }
    if ($stillRunning.Count -gt 0) {
        Write-Report 'RESULT: B_STILL_RUNNING - close B normally; this script does not terminate processes.'
        exit 2
    }
    Write-Report 'RESULT: B_STOPPED_PASS'
    exit 0
}

if ($Mode -eq 'RestoreBWindow') {
    $before = @(Get-BProcesses -BWebData $webData)
    if ($before.Count -eq 0) {
        Stop-WithReport 'No B process is available to restore. Use QualifyB or Coexistence instead.'
    }
    $beforeIds = @($before.ProcessId)
    $beforeRoots = @($before | Where-Object { $beforeIds -notcontains $_.ParentProcessId })
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $target.Executable
    $psi.Arguments = "--user-data-dir=`"$webData`" --new-window"
    $psi.WorkingDirectory = $profileRoot
    $psi.UseShellExecute = $false
    $psi.Environment['CODEX_HOME'] = $codexHome
    $psi.Environment['CODEX_SQLITE_HOME'] = $sqliteHome
    Write-Report "B roots before restore: $($beforeRoots.Count)"
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        Stop-WithReport "B window restore failed (including AccessDenied): $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 6
    $after = @(Get-BProcesses -BWebData $webData)
    $afterIds = @($after.ProcessId)
    $afterRoots = @($after | Where-Object { $afterIds -notcontains $_.ParentProcessId })
    Write-Report "B roots after restore: $($afterRoots.Count)"
    Write-Report "B processes after restore: $($after.Count)"
    if ($afterRoots.Count -gt $beforeRoots.Count) {
        Stop-WithReport 'Restore created an additional B root; do not open projects or log in again.'
    }
    Write-Report 'RESULT: RESTORE_REQUESTED - manually confirm B is visible; no login or project action was performed.'
    exit 0
}

$existing = @(Get-NamedDesktopProcesses)
if ($Mode -eq 'QualifyB' -and $existing.Count -gt 0) {
    Stop-WithReport 'QualifyB requires A to be closed: ChatGPT processes are present. B was not launched.'
}
if ($Mode -eq 'Coexistence' -and $existing.Count -lt 1) {
    Stop-WithReport 'Coexistence requires A to be open: no ChatGPT process was found. B was not launched.'
}

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $target.Executable
$psi.Arguments = "--user-data-dir=`"$webData`" --new-window"
$psi.WorkingDirectory = $profileRoot
$psi.UseShellExecute = $false
$psi.Environment['CODEX_HOME'] = $codexHome
$psi.Environment['CODEX_SQLITE_HOME'] = $sqliteHome

Write-Report 'Launching B without login.'
try {
    $started = [System.Diagnostics.Process]::Start($psi)
} catch {
    Stop-WithReport "Avvio diretto fallito (incluso AccessDenied): $($_.Exception.Message). Nessun fallback viene tentato."
}
Start-Sleep -Seconds 12
$bProcesses = @(Get-BProcesses -BWebData $webData)
Write-Report "Launch PID: $($started.Id)"
Write-Report "Processes referencing B web-data: $($bProcesses.Count)"
foreach ($process in $bProcesses) { Write-Report "B PID: $($process.ProcessId); Parent: $($process.ParentProcessId)" }
foreach ($path in @($codexHome, $sqliteHome, $webData)) {
    $count = @(Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction Stop).Count
    Write-Report "B entries under ${path}: $count"
}
if ($bProcesses.Count -eq 0) { Stop-WithReport 'Nessun processo osservabile riferisce il web-data B; non proseguire.' }

Write-Report 'MANUAL: conferma la finestra B senza login; poi chiudila manualmente.'
if ($NoWait) {
    Write-Report 'RESULT: LAUNCHED_AWAITING_MANUAL_CLOSE'
    exit 0
}
Read-Host 'Dopo la chiusura di B, premi Invio' | Out-Null
$remaining = @(Get-BProcesses -BWebData $webData)
if ($remaining.Count -gt 0) { Stop-WithReport 'B risulta ancora attivo. Chiudilo manualmente; lo script non termina processi.' }
Write-Report 'RESULT: OBSERVATION_COMPLETED'
Write-Report 'LIMIT: questo prova solo il lancio osservato con argomenti B e scritture sotto B. Non prova assenza di scritture altrove, isolamento completo del backend, due account indipendenti, ne persistenza del login.'
