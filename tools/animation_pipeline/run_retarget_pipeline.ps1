param(
    [string]$BlenderExe = "",
    [string]$PythonExe = "python",
    [string]$Config = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$scriptPath = Join-Path $PSScriptRoot "run_retarget_pipeline.py"

$argsList = @(
    $scriptPath,
    "--repo-root", $repoRoot
)

if (-not [string]::IsNullOrWhiteSpace($BlenderExe)) {
    $argsList += @("--blender-exe", $BlenderExe)
}
if (-not [string]::IsNullOrWhiteSpace($Config)) {
    $argsList += @("--config", $Config)
}

& $PythonExe @argsList

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
