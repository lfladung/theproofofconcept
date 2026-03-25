param(
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8787,
    [int]$StaleAfterSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $scriptDir "instance_registry\run_registry.ps1"

& $runner -BindHost $BindHost -Port $Port -StaleAfterSeconds $StaleAfterSeconds
$exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
exit $exitCode
