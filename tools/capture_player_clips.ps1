param(
    [string[]]$Modes = @("idle", "walk", "attack"),
    [int]$Fps = 30,
    [double]$DurationSeconds = 3.0,
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

$scenePath = "res://scenes/tools/player_visual_capture.tscn"
$videosDir = Join-Path $repoRoot "logs\\captures\\videos"
if (-not (Test-Path $videosDir)) {
    New-Item -ItemType Directory -Path $videosDir -Force | Out-Null
}

$expandedModes = @()
foreach ($raw in $Modes) {
    $parts = @($raw.ToString().Split(",", [System.StringSplitOptions]::RemoveEmptyEntries))
    foreach ($part in $parts) {
        $trimmed = $part.Trim().ToLower()
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            $expandedModes += $trimmed
        }
    }
}
if ($expandedModes.Count -eq 0) {
    $expandedModes = @("idle", "walk", "attack")
}

$frameCount = [Math]::Max(1, [int][Math]::Round($Fps * $DurationSeconds))
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "Godot:      $GodotExe"
Write-Host "Project:    $repoRoot"
Write-Host "CaptureDir: $videosDir"
Write-Host "FPS:        $Fps"
Write-Host "Frames:     $frameCount"

foreach ($modeRaw in $expandedModes) {
    $mode = $modeRaw.ToLower()
    $outFile = Join-Path $videosDir ("{0}_{1}.avi" -f $mode, $timestamp)

    $cmdArgs = @(
        "--path", $repoRoot,
        "--scene", $scenePath,
        "--write-movie", $outFile,
        "--fixed-fps", "$Fps",
        "--disable-vsync",
        "--quit-after", "$frameCount",
        "--",
        "--mode=$mode",
        "--auto_quit=false",
        "--camera_yaw=$CameraYaw",
        "--camera_pitch=$CameraPitch",
        "--camera_distance=$CameraDistance",
        "--camera_height_offset=$CameraHeightOffset"
    )

    Write-Host ""
    Write-Host "Capturing mode='$mode' -> $outFile"
    Write-Host "Args: $($cmdArgs -join ' ')"

    & $GodotExe @cmdArgs
    $exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    if ($exitCode -ne 0) {
        Write-Error "Godot capture failed for mode '$mode' with exit code $exitCode"
        exit $exitCode
    }

    if (-not (Test-Path $outFile)) {
        Write-Error "Video capture did not produce output file: $outFile"
        exit 1
    }
}

Write-Host ""
Write-Host "Done. Captured clips in $videosDir"
