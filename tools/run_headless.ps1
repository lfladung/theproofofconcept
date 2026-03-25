param(
	[string]$GodotExe = "",
	[string]$ProjectPath = "",
	[switch]$CheckOnly,
	[string]$Script = "",
	[switch]$NoQuit,
	[string]$ProfileDir = "",
	[switch]$VerboseOutput,
	[Parameter(ValueFromRemainingArguments = $true)]
	[string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
	$GodotExe = Join-Path $repoRoot "Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe"
}
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
	$ProjectPath = $repoRoot
} elseif (-not [System.IO.Path]::IsPathRooted($ProjectPath)) {
	$ProjectPath = Join-Path $repoRoot $ProjectPath
}
if ([string]::IsNullOrWhiteSpace($ProfileDir)) {
	$ProfileDir = Join-Path $repoRoot ".godot_cli_profile"
} elseif (-not [System.IO.Path]::IsPathRooted($ProfileDir)) {
	$ProfileDir = Join-Path $repoRoot $ProfileDir
}

$GodotExe = (Resolve-Path $GodotExe).Path
$ProjectPath = (Resolve-Path $ProjectPath).Path
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
$ProfileDir = (Resolve-Path $ProfileDir).Path

$env:APPDATA = $ProfileDir
$env:LOCALAPPDATA = $ProfileDir

$godotArgs = @("--headless", "--path", $ProjectPath)
if ($VerboseOutput) {
	$godotArgs += "--verbose"
}
if ($CheckOnly) {
	if ([string]::IsNullOrWhiteSpace($Script)) {
		Write-Error "When using -CheckOnly, provide -Script <res://...>. Example: -Script res://dungeon/game/small_dungeon.gd"
		exit 2
	}
	$godotArgs += @("--check-only", "--script", $Script)
}
if (-not $NoQuit) {
	$godotArgs += "--quit"
}
if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
	$godotArgs += $ExtraArgs
}

Write-Host ("Godot:    {0}" -f $GodotExe)
Write-Host ("Project:  {0}" -f $ProjectPath)
Write-Host ("Profile:  {0}" -f $ProfileDir)
Write-Host ("Args:     {0}" -f ($godotArgs -join " "))

& $GodotExe @godotArgs
exit $LASTEXITCODE
