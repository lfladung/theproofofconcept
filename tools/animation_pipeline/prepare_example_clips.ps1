param(
    [string]$AttackVideo = "$env:USERPROFILE\Videos\attackExample.mp4",
    [string]$WalkVideo = "$env:USERPROFILE\Videos\walkingExample.mp4",
    [string]$DefendVideo = "$env:USERPROFILE\Videos\defendexample.mp4",
    [int]$Fps = 30,
    [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$scriptPath = Join-Path $PSScriptRoot "prepare_example_clips.py"

& $PythonExe $scriptPath `
    --repo-root $repoRoot `
    --fps $Fps `
    --attack-video $AttackVideo `
    --walk-video $WalkVideo `
    --defend-video $DefendVideo

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
