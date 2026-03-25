param(
    [string]$GodotExe = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $GodotExe = Join-Path $repoRoot "Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
}
$GodotExe = (Resolve-Path $GodotExe).Path

$args = @("--path", $repoRoot)

Write-Host "Godot:   $GodotExe"
Write-Host "Project: $repoRoot"
Write-Host "Args:    $($args -join ' ')"

& $GodotExe @args
$exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
exit $exitCode
