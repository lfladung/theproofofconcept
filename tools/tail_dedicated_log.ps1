param(
    [int]$WaitTimeoutSeconds = 0,
    [string]$LogFile = "",
    [switch]$NoFollow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path

if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $explicitLogPath = Join-Path $repoRoot "dedicated_server.log"
} elseif ([System.IO.Path]::IsPathRooted($LogFile)) {
    $explicitLogPath = $LogFile
} else {
    $explicitLogPath = Join-Path $repoRoot $LogFile
}

$candidates = @(
    $explicitLogPath,
    (Join-Path $env:APPDATA "Godot\app_userdata"),
    (Join-Path $env:LOCALAPPDATA "Godot\app_userdata"),
    (Join-Path $repoRoot ".godot_cli_profile\Godot\app_userdata"),
    (Join-Path $repoRoot ".godot_cli_profile\app_userdata")
)

$deadline = if ($WaitTimeoutSeconds -gt 0) { (Get-Date).AddSeconds($WaitTimeoutSeconds) } else { $null }
$logPath = $null

while ($true) {
    if (Test-Path $explicitLogPath) {
        $logPath = (Resolve-Path $explicitLogPath).Path
        break
    }

    $roots = $candidates | Where-Object { $_ -ne $explicitLogPath }
    $found = @(
        Get-ChildItem $roots -Recurse -Filter "dedicated_server.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    if ($found.Count -gt 0) {
        $logPath = $found[0].FullName
        break
    }

    if ($deadline -ne $null -and (Get-Date) -gt $deadline) {
        Write-Error @"
No dedicated_server.log found before timeout.
Start the dedicated server first and check these locations:
$($candidates -join "`n")
"@
        exit 1
    }

    Start-Sleep -Seconds 1
}

Write-Host "Log file: $logPath"
if ($NoFollow) {
    Get-Content $logPath
} else {
    Get-Content $logPath -Wait
}
