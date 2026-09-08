[CmdletBinding()]
param(
    [string]$Root = 'C:\CodexDual'
)

# Metadata-only observation of the already configured B instance.
# Never launches or closes Codex, reads credentials, or inspects profile A.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$profileRoot = Join-Path $Root 'profiles\B'
$webData = Join-Path $profileRoot 'web-data'
$stateDir = Join-Path $Root 'state'
$receiptPath = Join-Path $stateDir 'B-process-receipt.json'

if (-not (Test-Path -LiteralPath $webData)) { throw "Percorso B mancante: $webData" }

if (-not ('CodexDual.WindowProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace CodexDual {
    public static class WindowProbe {
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint command);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        private const uint GW_OWNER = 4;

        public static IntPtr[] GetVisibleUnownedTopLevelWindows() {
            var windows = new List<IntPtr>();
            EnumWindows((hWnd, lParam) => {
                if (IsWindowVisible(hWnd) && GetWindow(hWnd, GW_OWNER) == IntPtr.Zero) windows.Add(hWnd);
                return true;
            }, IntPtr.Zero);
            return windows.ToArray();
        }

        public static uint GetOwnerProcessId(IntPtr hWnd) {
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            return processId;
        }
    }
}
'@
}

try {
    $bProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.CommandLine -and $_.CommandLine.IndexOf($webData, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
} catch {
    throw "Impossibile leggere i processi B (AccessDenied o errore CIM): $($_.Exception.Message)"
}

$bPids = @($bProcesses.ProcessId)
$windows = @(
    [CodexDual.WindowProbe]::GetVisibleUnownedTopLevelWindows() | ForEach-Object {
        $windowPid = [CodexDual.WindowProbe]::GetOwnerProcessId($_)
        if ($bPids -contains [int]$windowPid) {
            [pscustomobject]@{
                hwnd = ('0x{0:X}' -f $_.ToInt64())
                pid = [int]$windowPid
            }
        }
    }
)

$known = @(
    foreach ($process in $bProcesses) {
        [pscustomobject]@{
            pid = [int]$process.ProcessId
            parentPid = [int]$process.ParentProcessId
            startTime = if ($process.CreationDate -is [datetime]) { $process.CreationDate.ToString('o') } elseif ($process.CreationDate) { ([Management.ManagementDateTimeConverter]::ToDateTime([string]$process.CreationDate)).ToString('o') } else { $null }
            executablePath = $process.ExecutablePath
            evidence = @('user-data-dir-command-line')
        }
    }
)

$receipt = [pscustomobject]@{
    schemaVersion = 1
    profile = 'B'
    state = if ($windows.Count -gt 0) { 'UI_VISIBLE' } elseif ($known.Count -gt 0) { 'BACKGROUND_PENDING' } else { 'NOT_RUNNING' }
    observedAt = (Get-Date).ToString('o')
    userDataDir = $webData
    knownBProcesses = $known
    windows = $windows
    privacy = 'No credential values, auth files, window titles, chat content, or project content recorded.'
    limit = 'Ownership is based on the B user-data marker and window PID mapping; this receipt does not authorize process termination.'
}

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
[System.IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
Write-Output "RESULT: RECEIPT_CREATED - $receiptPath"
Write-Output "B processes: $($known.Count); visible B windows: $($windows.Count); state: $($receipt.state)"
