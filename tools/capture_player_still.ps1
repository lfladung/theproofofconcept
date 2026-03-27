param(
    [string]$Mode = "idle",
    [string]$OutFile = "",
    [double]$ScreenshotTime = 0.85,
    [double]$CameraYaw = 145,
    [double]$CameraPitch = -28,
    [double]$CameraDistance = 9.0,
    [double]$CameraHeightOffset = 1.2,
    [string]$GodotExe = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $candidates = @(
        (Join-Path $repoRoot "Godot_v4.6.1-stable_win64.exe\\Godot_v4.6.1-stable_win64_console.exe"),
        (Join-Path $repoRoot "Godot_v4.6.1-stable_win64.exe\\Godot_v4.6.1-stable_win64.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            $GodotExe = $candidate
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GodotExe) -or -not (Test-Path $GodotExe)) {
    throw "Could not find Godot executable. Pass -GodotExe explicitly."
}
$GodotExe = (Resolve-Path $GodotExe).Path

$capturesDir = Join-Path $repoRoot "logs\\captures\\stills"
if (-not (Test-Path $capturesDir)) {
    New-Item -ItemType Directory -Path $capturesDir -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeMode = $Mode.ToLower()
    $OutFile = Join-Path $capturesDir ("{0}_{1}.png" -f $safeMode, $timestamp)
}

$scenePath = "res://scenes/tools/player_visual_capture.tscn"
$quitAfterFrames = 480
$cmdArgs = @(
    "--path", $repoRoot,
    "--scene", $scenePath,
    "--quit-after", "$quitAfterFrames",
    "--",
    "--mode=$Mode",
    "--screenshot_path=$OutFile",
    "--screenshot_time=$ScreenshotTime",
    "--auto_quit=true",
    "--camera_yaw=$CameraYaw",
    "--camera_pitch=$CameraPitch",
    "--camera_distance=$CameraDistance",
    "--camera_height_offset=$CameraHeightOffset"
)

Write-Host "Godot:   $GodotExe"
Write-Host "Project: $repoRoot"
Write-Host "Output:  $OutFile"
Write-Host "Args:    $($cmdArgs -join ' ')"

& $GodotExe @cmdArgs
$exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
if ($exitCode -ne 0) {
    exit $exitCode
}

if (-not (Test-Path $OutFile)) {
    Write-Error "Still capture did not produce output file: $OutFile"
    exit 1
}

Write-Host "Saved: $OutFile"
