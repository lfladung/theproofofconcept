param(
    [string]$BlenderExe = "",
    [switch]$SkipFbx = $false
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")

$pythonArgs = @(
    "tools/animation_pipeline/video_to_mocap_fbx.py",
    "--repo-root", $repoRoot.Path
)
if ($BlenderExe -ne "") {
    $pythonArgs += @("--blender-exe", $BlenderExe)
}
if ($SkipFbx) {
    $pythonArgs += "--skip-fbx"
}

$clips = @(
    @{
        Name = "attack"
        Action = "Attack_Mocap"
        Candidates = @("AttackV2.mov", "AttackV2.mp4", "attack.mov", "attack.mp4")
    },
    @{
        Name = "walk"
        Action = "Walk_Mocap"
        Candidates = @("WalkingV2.mov", "WalkingV2.mp4", "walk.mov", "walk.mp4")
    },
    @{
        Name = "defend"
        Action = "Defend_Mocap"
        Candidates = @("DefendV2.mov", "DefendV2.mp4", "defend.mov", "defend.mp4")
    }
)

foreach ($clip in $clips) {
    $videoPath = $null
    foreach ($candidate in $clip.Candidates) {
        $candidatePath = Join-Path $repoRoot.Path ("tools/animation_pipeline/work/videos/{0}" -f $candidate)
        if (Test-Path $candidatePath) {
            $videoPath = $candidatePath
            break
        }
    }
    if ($null -eq $videoPath) {
        throw ("Missing staged video for {0}. Tried: {1}" -f $clip.Name, ($clip.Candidates -join ", "))
    }
    $jsonPath = Join-Path $repoRoot.Path ("tools/animation_pipeline/work/mocap/{0}.pose.json" -f $clip.Name)
    $fbxPath = Join-Path $repoRoot.Path ("tools/animation_pipeline/work/mocap/{0}.fbx" -f $clip.Name)

    Write-Host ("[mocap] converting {0} from {1}" -f $clip.Name, (Split-Path -Leaf $videoPath)) -ForegroundColor Cyan
    & python @pythonArgs `
        --input-video $videoPath `
        --output-json $jsonPath `
        --output-fbx $fbxPath `
        --action-name $clip.Action
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if ($SkipFbx) {
    Write-Host "Mocap JSON extraction complete." -ForegroundColor Green
} else {
    Write-Host "Mocap FBX export complete: tools/animation_pipeline/work/mocap/*.fbx" -ForegroundColor Green
}
