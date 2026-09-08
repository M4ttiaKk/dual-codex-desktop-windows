[CmdletBinding()]
param(
    [string]$Root = 'C:\CodexDual',
    [ValidateRange(15, 300)][int]$DurationSeconds = 120,
    [ValidateRange(1, 10)][int]$PollSeconds = 1
)

# Observe B window closure only. This script never starts, closes, or terminates
# Codex processes and never reads credentials, titles, chats, or project content.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$receiptScript = Join-Path $Root 'scripts\lifecycle\Get-CodexBReceipt.ps1'
$receiptPath = Join-Path $Root 'state\B-process-receipt.json'
$reportDir = Join-Path $Root 'reports'
if (-not (Test-Path -LiteralPath $receiptScript)) { throw "Receipt script mancante: $receiptScript" }
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$report = Join-Path $reportDir ("LifecycleWatch-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')

function Write-Watch {
    param([Parameter(Mandatory)][string]$Text)
    $Text | Tee-Object -FilePath $report -Append
}

function Get-Receipt {
    & $receiptScript -Root $Root | Out-Null
    Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
}

$initial = Get-Receipt
Write-Watch "Lifecycle B window watch started: $(Get-Date -Format o)"
Write-Watch "Initial state: $($initial.state); B processes: $(@($initial.knownBProcesses).Count); visible B windows: $(@($initial.windows).Count)"
if ($initial.state -ne 'UI_VISIBLE') {
    Write-Watch 'RESULT: STOP - B is not visibly open; no close event can be observed.'
    exit 2
}

$deadline = (Get-Date).AddSeconds($DurationSeconds)
$closedPolls = 0
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $PollSeconds
    $current = Get-Receipt
    $visible = @($current.windows).Count
    if ($visible -eq 0) {
        $closedPolls++
        Write-Watch "Closed-window poll $closedPolls/3; B processes: $(@($current.knownBProcesses).Count); state: $($current.state)"
        if ($closedPolls -ge 3) {
            Write-Watch 'RESULT: UI_CLOSED_OBSERVED - B window closed while no process was terminated by this monitor.'
            Write-Watch "Remaining B processes: $(@($current.knownBProcesses).Count)"
            Write-Watch "Report: $report"
            exit 0
        }
    } else {
        $closedPolls = 0
    }
}

Write-Watch 'RESULT: TIMEOUT - no stable B window closure was observed; no action was taken.'
Write-Watch "Report: $report"
exit 3
