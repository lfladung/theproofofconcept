param(
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8787,
    [int]$StaleAfterSeconds = 20
)

$scriptPath = "$PSScriptRoot\instance_registry_server.py"
$psFallbackScriptPath = "$PSScriptRoot\instance_registry_server.ps1"

function Test-CommandWorks {
    param(
        [string]$Exe,
        [string[]]$Args
    )

    if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) {
        return $false
    }

    & $Exe @Args *> $null
    return ($LASTEXITCODE -eq 0)
}

if (Test-CommandWorks -Exe "py" -Args @("-3", "-V")) {
    py -3 $scriptPath --host=$BindHost --port=$Port --stale-after-seconds=$StaleAfterSeconds
    exit $LASTEXITCODE
}

if (Test-CommandWorks -Exe "python" -Args @("-V")) {
    python $scriptPath --host=$BindHost --port=$Port --stale-after-seconds=$StaleAfterSeconds
    exit $LASTEXITCODE
}

if (Test-Path $psFallbackScriptPath) {
    Write-Warning "Python is unavailable. Falling back to PowerShell instance registry."
    & $psFallbackScriptPath -BindHost $BindHost -Port $Port -StaleAfterSeconds $StaleAfterSeconds
    $exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    exit $exitCode
}

Write-Error "Python is unavailable and PowerShell fallback registry script is missing: $psFallbackScriptPath"
exit 1
