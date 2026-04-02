param(
    [string]$OutDir = "",
    [string]$RoomNames = "",
    [int]$RoomLimit = 6,
    [double]$SettleSeconds = 0.6,
    [double]$CameraYaw = 180,
    [double]$CameraPitch = -72,
    [double]$CameraDistance = 160.0,
    [string]$CameraProjection = "orthogonal",
    [double]$CameraSizeMultiplier = 0.7,
    [double]$CameraHeightOffset = 0.0,
    [int]$WindowWidth = 1600,
    [int]$WindowHeight = 900,
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

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutDir = Join-Path $repoRoot ("logs\\captures\\floors\\{0}" -f $timestamp)
}

$scenePath = "res://scenes/tools/dungeon_floor_capture.tscn"
$quitAfterFrames = 2400
$cmdArgs = @(
    "--path", $repoRoot,
    "--scene", $scenePath,
    "--quit-after", "$quitAfterFrames",
    "--",
    "--output_dir=$OutDir",
    "--room_limit=$RoomLimit",
    "--settle_seconds=$SettleSeconds",
    "--camera_yaw=$CameraYaw",
    "--camera_pitch=$CameraPitch",
    "--camera_distance=$CameraDistance",
    "--camera_projection=$CameraProjection",
    "--camera_size_multiplier=$CameraSizeMultiplier",
    "--camera_height_offset=$CameraHeightOffset",
    "--window_width=$WindowWidth",
    "--window_height=$WindowHeight"
)

if (-not [string]::IsNullOrWhiteSpace($RoomNames)) {
    $cmdArgs += "--room_names=$RoomNames"
}

Write-Host "Godot:   $GodotExe"
Write-Host "Project: $repoRoot"
Write-Host "Output:  $OutDir"
Write-Host "Args:    $($cmdArgs -join ' ')"

& $GodotExe @cmdArgs
$exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
if ($exitCode -ne 0) {
    exit $exitCode
}

$reportPath = Join-Path $OutDir "report.json"
if (-not (Test-Path $reportPath)) {
    Write-Error "Dungeon floor capture did not produce report: $reportPath"
    exit 1
}

Write-Host "Saved report: $reportPath"
