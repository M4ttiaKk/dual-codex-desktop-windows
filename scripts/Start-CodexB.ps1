[CmdletBinding()]
param()

# Starts or requests a window for the existing B profile. It does not read
# credentials, close any process, alter A, or attempt a login.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = 'C:\CodexDual'
$profileRoot = Join-Path $root 'profiles\B'
$codexHome = Join-Path $profileRoot 'codex-home'
$sqliteHome = Join-Path $codexHome 'sqlite'
$webData = Join-Path $profileRoot 'web-data'
$marker = Join-Path $profileRoot 'PHASE1-PREPARED.txt'

function Stop-Launch {
    param([Parameter(Mandatory)][string]$Message)
    Write-Error $Message
    exit 1
}

foreach ($path in @($root, $profileRoot, $codexHome, $sqliteHome, $webData, $marker)) {
    if (-not (Test-Path -LiteralPath $path)) {
        Stop-Launch "Percorso B mancante: $path. Nessun avvio eseguito."
    }
}

try {
    $bProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.CommandLine -and $_.CommandLine.IndexOf($webData, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
} catch {
    Stop-Launch "Impossibile leggere i processi B (AccessDenied o errore CIM): $($_.Exception.Message)"
}

$package = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { Stop-Launch 'OpenAI.Codex non e installato per l utente corrente.' }
$exe = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
if (-not (Test-Path -LiteralPath $exe)) { Stop-Launch "ChatGPT.exe non trovato: $exe" }

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $exe
$psi.Arguments = "--user-data-dir=`"$webData`" --new-window"
$psi.WorkingDirectory = $profileRoot
$psi.UseShellExecute = $false
$psi.Environment['CODEX_HOME'] = $codexHome
$psi.Environment['CODEX_SQLITE_HOME'] = $sqliteHome

if ($bProcesses.Count -gt 0) {
    $beforeIds = @($bProcesses.ProcessId)
    $beforeRoots = @($bProcesses | Where-Object { $beforeIds -notcontains $_.ParentProcessId })
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        Start-Sleep -Seconds 6
        $after = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.CommandLine -and $_.CommandLine.IndexOf($webData, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $afterIds = @($after.ProcessId)
        $afterRoots = @($after | Where-Object { $afterIds -notcontains $_.ParentProcessId })
        if ($afterRoots.Count -gt $beforeRoots.Count) {
            Stop-Launch 'La richiesta di mostrare B ha creato un root B aggiuntivo. Non aprire progetti o avviare altri collegamenti; verifica manualmente le finestre.'
        }
        Write-Output 'Richiesta di riportare in primo piano Codex B inviata. Verifica manualmente la finestra e l account B.'
        exit 0
    } catch {
        Stop-Launch "Impossibile richiedere la finestra B (incluso AccessDenied): $($_.Exception.Message)"
    }
}

try {
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Write-Output 'Richiesta di avvio di Codex B inviata. Verifica manualmente la finestra e l account B.'
} catch {
    Stop-Launch "Avvio B non riuscito (incluso AccessDenied): $($_.Exception.Message). Nessun fallback tentato."
}
