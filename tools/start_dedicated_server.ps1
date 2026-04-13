param(
    [int]$Port = 7000,
    [bool]$AutoSelectPortWhenBusy = $true,
    [int]$PortSearchCount = 100,
    [int]$MaxPlayers = 6,
    [bool]$StartInRun = $false,
    [int]$ServerLogIntervalMs = 1500,
    [string]$RegistryUrl = "http://127.0.0.1:8787",
    [bool]$AutoStartRegistry = $true,
    [int]$RegistryReadyTimeoutSeconds = 30,
    [int]$RegistryStaleAfterSeconds = 20,
    [string]$RegistryLogFile = "",
    [string]$PublicHost = "127.0.0.1",
    [string]$SessionCode = "",
    [string]$InstanceId = "",
    [int]$EmptyShutdownSeconds = 20,
    [string]$AllocatorLogDir = "",
    [bool]$LaunchBootstrapInstance = $false,
    [string]$EngineLogFile = "",
    [string]$DedicatedLogFile = "",
    [string]$GodotExe = "",
    [switch]$UseDesktopExe,
    [switch]$Detached
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-RegistryHealth {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 2
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $healthUrl = $Url.TrimEnd("/") + "/health"
    try {
        $invokeParams = @{
            Uri = $healthUrl
            Method = "Get"
            TimeoutSec = $TimeoutSeconds
            ErrorAction = "Stop"
        }
        $webRequestCommand = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
        if ($null -ne $webRequestCommand -and $webRequestCommand.Parameters.ContainsKey("UseBasicParsing")) {
            $invokeParams["UseBasicParsing"] = $true
        }

        $response = Invoke-WebRequest @invokeParams
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300)
    } catch {
        return $false
    }
}

function Test-RegistryAllocatorReady {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 2
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $endpoint = $Url.TrimEnd("/") + "/v1/lobbies/create"
    $payload = @{ dry_run = $true } | ConvertTo-Json -Compress
    try {
        $invokeParams = @{
            Uri = $endpoint
            Method = "Post"
            Body = $payload
            ContentType = "application/json"
            TimeoutSec = $TimeoutSeconds
            ErrorAction = "Stop"
        }
        $response = Invoke-RestMethod @invokeParams
        if ($null -eq $response) {
            return $false
        }
        if ($response -is [System.Collections.IDictionary]) {
            return [bool]($response["ok"] -and $response["supports_create_lobby"])
        }
        $ok = $false
        $supports = $false
        if ($null -ne $response.PSObject.Properties["ok"]) {
            $ok = [bool]$response.ok
        }
        if ($null -ne $response.PSObject.Properties["supports_create_lobby"]) {
            $supports = [bool]$response.supports_create_lobby
        }
        return ($ok -and $supports)
    } catch {
        return $false
    }
}

function Get-ListeningProcessId {
    param([int]$TargetPort)

    $getConn = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
    if ($null -eq $getConn) {
        return 0
    }
    try {
        $row = Get-NetTCPConnection -State Listen -LocalPort $TargetPort -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $row) {
            return 0
        }
        return [int]$row.OwningProcess
    } catch {
        return 0
    }
}

function Get-RegistryEndpoint {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null
    }

    try {
        $uri = [System.Uri]$Url
    } catch {
        return $null
    }

    $port = if ($uri.IsDefaultPort) {
        if ($uri.Scheme -ieq "https") { 443 } else { 80 }
    } else {
        $uri.Port
    }

    return @{
        BindHost = $uri.Host
        Port = $port
        IsLocal = @("127.0.0.1", "localhost", "::1") -contains $uri.Host.ToLowerInvariant()
    }
}

function Get-RegistryStartCandidates {
    param(
        [string]$ScriptDir,
        [string]$BindHost,
        [int]$BindPort,
        [int]$StaleAfterSeconds,
        [string]$SpawnGodotExe,
        [string]$SpawnProjectPath,
        [string]$SpawnRegistryUrl,
        [string]$SpawnPublicHost,
        [int]$SpawnBasePort,
        [int]$SpawnPortSearchCount,
        [int]$SpawnDefaultMaxPlayers,
        [int]$SpawnServerLogIntervalMs,
        [int]$SpawnEmptyShutdownSeconds,
        [string]$SpawnLogDir
    )

    $candidates = @()
    $pythonRegistryScript = Join-Path $ScriptDir "instance_registry\instance_registry_server.py"
    $psRegistryScript = Join-Path $ScriptDir "instance_registry\instance_registry_server.ps1"

    if (Test-Path $pythonRegistryScript) {
        $pyCmd = Get-Command py -ErrorAction SilentlyContinue
        if ($null -ne $pyCmd) {
            $candidates += @{
                Name = "py"
                FilePath = $pyCmd.Source
                Args = @(
                    "-3",
                    $pythonRegistryScript,
                    "--host=$BindHost",
                    "--port=$BindPort",
                    "--stale-after-seconds=$StaleAfterSeconds",
                    "--spawn-godot-exe=$SpawnGodotExe",
                    "--spawn-project-path=$SpawnProjectPath",
                    "--spawn-registry-url=$SpawnRegistryUrl",
                    "--spawn-public-host=$SpawnPublicHost",
                    "--spawn-base-port=$SpawnBasePort",
                    "--spawn-port-search-count=$SpawnPortSearchCount",
                    "--spawn-default-max-players=$SpawnDefaultMaxPlayers",
                    "--spawn-server-log-interval-ms=$SpawnServerLogIntervalMs",
                    "--spawn-empty-shutdown-seconds=$SpawnEmptyShutdownSeconds",
                    "--spawn-log-dir=$SpawnLogDir"
                )
            }
        }

        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if ($null -ne $pythonCmd) {
            $candidates += @{
                Name = "python"
                FilePath = $pythonCmd.Source
                Args = @(
                    $pythonRegistryScript,
                    "--host=$BindHost",
                    "--port=$BindPort",
                    "--stale-after-seconds=$StaleAfterSeconds",
                    "--spawn-godot-exe=$SpawnGodotExe",
                    "--spawn-project-path=$SpawnProjectPath",
                    "--spawn-registry-url=$SpawnRegistryUrl",
                    "--spawn-public-host=$SpawnPublicHost",
                    "--spawn-base-port=$SpawnBasePort",
                    "--spawn-port-search-count=$SpawnPortSearchCount",
                    "--spawn-default-max-players=$SpawnDefaultMaxPlayers",
                    "--spawn-server-log-interval-ms=$SpawnServerLogIntervalMs",
                    "--spawn-empty-shutdown-seconds=$SpawnEmptyShutdownSeconds",
                    "--spawn-log-dir=$SpawnLogDir"
                )
            }
        }
    }

    if (Test-Path $psRegistryScript) {
        $shellPath = (Get-Process -Id $PID).Path
        if (-not [string]::IsNullOrWhiteSpace($shellPath)) {
            $candidates += @{
                Name = "powershell-fallback"
                FilePath = $shellPath
                Args = @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", $psRegistryScript,
                    "-BindHost", $BindHost,
                    "-Port", $BindPort,
                    "-StaleAfterSeconds", $StaleAfterSeconds,
                    "-SpawnGodotExe", $SpawnGodotExe,
                    "-SpawnProjectPath", $SpawnProjectPath,
                    "-SpawnRegistryUrl", $SpawnRegistryUrl,
                    "-SpawnPublicHost", $SpawnPublicHost,
                    "-SpawnBasePort", $SpawnBasePort,
                    "-SpawnPortSearchCount", $SpawnPortSearchCount,
                    "-SpawnDefaultMaxPlayers", $SpawnDefaultMaxPlayers,
                    "-SpawnServerLogIntervalMs", $SpawnServerLogIntervalMs,
                    "-SpawnEmptyShutdownSeconds", $SpawnEmptyShutdownSeconds,
                    "-SpawnLogDir", $SpawnLogDir
                )
            }
        }
    }

    return $candidates
}

function Wait-RegistryReady {
    param(
        [string]$Url,
        [int]$TimeoutSeconds,
        [int]$ProcessId = 0
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ($ProcessId -gt 0 -and $null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            return $false
        }
        if (Test-RegistryHealth -Url $Url -TimeoutSeconds 2) {
            return $true
        }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Test-TcpPortAvailable {
    param([int]$CandidatePort)

    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $CandidatePort)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

function Resolve-ServerPort {
    param(
        [int]$RequestedPort,
        [bool]$AutoSelectWhenBusy,
        [int]$SearchCount
    )

    if (Test-TcpPortAvailable -CandidatePort $RequestedPort) {
        return $RequestedPort
    }

    if (-not $AutoSelectWhenBusy) {
        throw "Requested port $RequestedPort is already in use. Set -AutoSelectPortWhenBusy \$true or choose a different -Port."
    }

    $safeSearchCount = [Math]::Max(1, $SearchCount)
    for ($offset = 1; $offset -le $safeSearchCount; $offset++) {
        $candidate = $RequestedPort + $offset
        if ($candidate -gt 65535) {
            break
        }
        if (Test-TcpPortAvailable -CandidatePort $candidate) {
            Write-Warning "Port $RequestedPort is in use. Using open port $candidate instead."
            return $candidate
        }
    }

    throw "Could not find an open port in range $RequestedPort-$([Math]::Min(65535, $RequestedPort + $safeSearchCount))."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
$logsRoot = Join-Path $repoRoot "logs"
if (-not (Test-Path $logsRoot)) {
    New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $exeName = if ($UseDesktopExe) {
        "Godot_v4.6.1-stable_win64.exe"
    } else {
        "Godot_v4.6.1-stable_win64_console.exe"
    }
    $GodotExe = Join-Path $repoRoot "Godot_v4.6.1-stable_win64.exe\$exeName"
}
$GodotExe = (Resolve-Path $GodotExe).Path

if ([string]::IsNullOrWhiteSpace($AllocatorLogDir)) {
    $AllocatorLogDir = $logsRoot
} elseif (-not [System.IO.Path]::IsPathRooted($AllocatorLogDir)) {
    $AllocatorLogDir = Join-Path $repoRoot $AllocatorLogDir
}
if (-not (Test-Path $AllocatorLogDir)) {
    New-Item -ItemType Directory -Path $AllocatorLogDir -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($EngineLogFile)) {
    $EngineLogFile = Join-Path $logsRoot "dedicated_server_engine.log"
} elseif (-not [System.IO.Path]::IsPathRooted($EngineLogFile)) {
    $EngineLogFile = Join-Path $repoRoot $EngineLogFile
}
$engineLogParent = Split-Path -Parent $EngineLogFile
if (-not [string]::IsNullOrWhiteSpace($engineLogParent) -and -not (Test-Path $engineLogParent)) {
    New-Item -ItemType Directory -Path $engineLogParent -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($DedicatedLogFile)) {
    $DedicatedLogFile = Join-Path $logsRoot "dedicated_server.log"
} elseif (-not [System.IO.Path]::IsPathRooted($DedicatedLogFile)) {
    $DedicatedLogFile = Join-Path $repoRoot $DedicatedLogFile
}
$dedicatedLogParent = Split-Path -Parent $DedicatedLogFile
if (-not [string]::IsNullOrWhiteSpace($dedicatedLogParent) -and -not (Test-Path $dedicatedLogParent)) {
    New-Item -ItemType Directory -Path $dedicatedLogParent -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($RegistryLogFile)) {
    $RegistryLogFile = Join-Path $logsRoot "instance_registry.log"
} elseif (-not [System.IO.Path]::IsPathRooted($RegistryLogFile)) {
    $RegistryLogFile = Join-Path $repoRoot $RegistryLogFile
}
$registryLogParent = Split-Path -Parent $RegistryLogFile
if (-not [string]::IsNullOrWhiteSpace($registryLogParent) -and -not (Test-Path $registryLogParent)) {
    New-Item -ItemType Directory -Path $registryLogParent -Force | Out-Null
}

if ($LaunchBootstrapInstance) {
    $resolvedPort = Resolve-ServerPort -RequestedPort $Port -AutoSelectWhenBusy $AutoSelectPortWhenBusy -SearchCount $PortSearchCount
    if ($resolvedPort -ne $Port) {
        Write-Host "Dedicated server port resolved: requested=$Port actual=$resolvedPort"
        $Port = $resolvedPort
    }
}

if ($AutoStartRegistry -and -not [string]::IsNullOrWhiteSpace($RegistryUrl)) {
    $registryEndpoint = Get-RegistryEndpoint -Url $RegistryUrl
    if ($null -eq $registryEndpoint) {
        throw "Invalid -RegistryUrl value: '$RegistryUrl'."
    }

    $registryHealthy = Test-RegistryHealth -Url $RegistryUrl -TimeoutSeconds 1
    $allocatorReady = $false
    if ($registryHealthy) {
        $allocatorReady = Test-RegistryAllocatorReady -Url $RegistryUrl -TimeoutSeconds 2
    }

    $shouldStartLocalRegistry = $false

    if ($registryHealthy -and $allocatorReady) {
        Write-Host "Registry is already running at $RegistryUrl"
    } elseif ($registryHealthy -and (-not $allocatorReady) -and $registryEndpoint.IsLocal) {
        Write-Warning "Local registry is reachable but does not support lobby allocation. Restarting it."
        $ownerPid = Get-ListeningProcessId -TargetPort $registryEndpoint.Port
        if ($ownerPid -gt 0) {
            try {
                Stop-Process -Id $ownerPid -Force -ErrorAction Stop
                Start-Sleep -Milliseconds 400
                Write-Host "Stopped old local registry process (PID $ownerPid)."
            } catch {
                Write-Host "Failed to stop old registry process PID ${ownerPid}: $($_.Exception.Message)"
            }
        }
        $shouldStartLocalRegistry = $true
    } elseif (-not $registryHealthy -and $registryEndpoint.IsLocal) {
        $shouldStartLocalRegistry = $true
    }

    if ($shouldStartLocalRegistry) {
        $registryErrLogFile = "$RegistryLogFile.err"

        if (Test-Path $RegistryLogFile) {
            Remove-Item $RegistryLogFile -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $registryErrLogFile) {
            Remove-Item $registryErrLogFile -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Registry not reachable; starting local registry at $RegistryUrl"
        Write-Host "Registry log:     $RegistryLogFile"
        Write-Host "Registry err log: $registryErrLogFile"

        $registryStartCandidates = Get-RegistryStartCandidates `
            -ScriptDir $scriptDir `
            -BindHost $registryEndpoint.BindHost `
            -BindPort $registryEndpoint.Port `
            -StaleAfterSeconds $RegistryStaleAfterSeconds `
            -SpawnGodotExe $GodotExe `
            -SpawnProjectPath $repoRoot `
            -SpawnRegistryUrl $RegistryUrl `
            -SpawnPublicHost $PublicHost `
            -SpawnBasePort $Port `
            -SpawnPortSearchCount $PortSearchCount `
            -SpawnDefaultMaxPlayers $MaxPlayers `
            -SpawnServerLogIntervalMs $ServerLogIntervalMs `
            -SpawnEmptyShutdownSeconds $EmptyShutdownSeconds `
            -SpawnLogDir $AllocatorLogDir

        if ($registryStartCandidates.Count -eq 0) {
            Write-Host "ERROR: No available registry launcher found (py/python/PowerShell fallback)."
            exit 1
        }

        $registryProc = $null
        $startedRegistry = $false
        foreach ($candidate in $registryStartCandidates) {
            Write-Host "Trying registry launcher: $($candidate.Name)"
            try {
                $registryProc = Start-Process `
                    -FilePath $candidate.FilePath `
                    -ArgumentList $candidate.Args `
                    -RedirectStandardOutput $RegistryLogFile `
                    -RedirectStandardError $registryErrLogFile `
                    -PassThru
            } catch {
                Write-Host "Launcher '$($candidate.Name)' failed to start: $($_.Exception.Message)"
                continue
            }

            if (Wait-RegistryReady -Url $RegistryUrl -TimeoutSeconds $RegistryReadyTimeoutSeconds -ProcessId $registryProc.Id) {
                $startedRegistry = $true
                break
            }

            $candidateAlive = $null -ne (Get-Process -Id $registryProc.Id -ErrorAction SilentlyContinue)
            Write-Host ("Launcher '{0}' did not become healthy (status: {1})." -f $candidate.Name, ($(if ($candidateAlive) { "running" } else { "exited" })))
            if ($candidateAlive) {
                Stop-Process -Id $registryProc.Id -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not $startedRegistry) {
            $stdoutTail = if (Test-Path $RegistryLogFile) { (Get-Content $RegistryLogFile -Tail 20) -join "`n" } else { "" }
            $stderrTail = if (Test-Path $registryErrLogFile) { (Get-Content $registryErrLogFile -Tail 20) -join "`n" } else { "" }
            Write-Host "ERROR: Registry failed to become healthy at $RegistryUrl. Check $RegistryLogFile and $registryErrLogFile."
            if (-not [string]::IsNullOrWhiteSpace($stdoutTail)) {
                Write-Host "Registry stdout tail:"
                Write-Host $stdoutTail
            }
            if (-not [string]::IsNullOrWhiteSpace($stderrTail)) {
                Write-Host "Registry stderr tail:"
                Write-Host $stderrTail
            }
            exit 1
        }

        Write-Host "Registry started (PID $($registryProc.Id))."
        $allocatorReady = Test-RegistryAllocatorReady -Url $RegistryUrl -TimeoutSeconds 2
    } else {
        if (-not $registryHealthy) {
            Write-Warning "Registry at $RegistryUrl is unreachable and not local. Auto-start skipped."
        } elseif (-not $allocatorReady) {
            Write-Warning "Registry at $RegistryUrl is running but missing allocator endpoint (/v1/lobbies/create)."
        }
    }

    if (-not (Test-RegistryAllocatorReady -Url $RegistryUrl -TimeoutSeconds 2)) {
        Write-Host "ERROR: Registry allocator endpoint is unavailable at $RegistryUrl."
        Write-Host "Ensure this project's updated registry is running before clients host lobbies."
        exit 1
    }
}

if (-not $LaunchBootstrapInstance) {
    Write-Host "Session allocator is ready."
    Write-Host "Lobby hosts can now create session codes; dedicated instances will spawn on demand."
    Write-Host "Allocator base port: $Port"
    Write-Host "Allocator logs:      $AllocatorLogDir"
    exit 0
}

$engineArgs = @(
    "--headless",
    "--path", $repoRoot,
    "--log-file", $EngineLogFile,
    "--" # Everything after this is available via OS.get_cmdline_user_args().
)

$userArgs = @(
    "--dedicated_server",
    "--port=$Port",
    "--max_players=$MaxPlayers",
    "--start_in_run=$($StartInRun.ToString().ToLower())",
    "--server_log_interval_ms=$ServerLogIntervalMs",
    "--dedicated_log_file=$DedicatedLogFile",
    "--empty_shutdown_seconds=$EmptyShutdownSeconds"
)

if (-not [string]::IsNullOrWhiteSpace($RegistryUrl)) {
    $userArgs += "--registry_url=$RegistryUrl"
    if (-not [string]::IsNullOrWhiteSpace($PublicHost)) {
        $userArgs += "--public_host=$PublicHost"
    }
    if (-not [string]::IsNullOrWhiteSpace($SessionCode)) {
        $userArgs += "--session_code=$SessionCode"
    }
    if (-not [string]::IsNullOrWhiteSpace($InstanceId)) {
        $userArgs += "--instance_id=$InstanceId"
    }
}

$args = @($engineArgs + $userArgs)

Write-Host "Godot:         $GodotExe"
Write-Host "Project:       $repoRoot"
Write-Host "Engine log:    $EngineLogFile"
Write-Host "Gameplay log:  $DedicatedLogFile"
Write-Host "Args:          $($args -join ' ')"

if ($Detached) {
    $proc = Start-Process -FilePath $GodotExe -ArgumentList $args -PassThru
    Start-Sleep -Seconds 2

    $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($null -eq $alive) {
        Write-Error "Dedicated process exited during startup. Check: $EngineLogFile"
        exit 1
    }

    Write-Host "Dedicated server started (PID $($proc.Id))."
    Write-Host "Tail gameplay log with: .\\tools\\tail_dedicated_log.ps1"
    Write-Host "Tail engine log with:   Get-Content '$EngineLogFile' -Wait"
    Write-Host "Stop server with:       Stop-Process -Id $($proc.Id)"
    exit 0
}

& $GodotExe @args
$exitCode = if (Test-Path variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
exit $exitCode
