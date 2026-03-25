param(
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8787,
    [int]$StaleAfterSeconds = 20,
    [string]$SpawnGodotExe = "",
    [string]$SpawnProjectPath = "",
    [string]$SpawnRegistryUrl = "",
    [string]$SpawnPublicHost = "127.0.0.1",
    [int]$SpawnBasePort = 7000,
    [int]$SpawnPortSearchCount = 500,
    [int]$SpawnDefaultMaxPlayers = 4,
    [int]$SpawnServerLogIntervalMs = 1500,
    [int]$SpawnEmptyShutdownSeconds = 20,
    [double]$SpawnReadyTimeoutSeconds = 8.0,
    [string]$SpawnLogDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NowUnix {
    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Has-Field {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $false
    }
    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-Field {
    param(
        $Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $Default
    }
    return $prop.Value
}

function ConvertTo-HashtableSafe {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $mapped = @{}
        foreach ($key in $Value.Keys) {
            $mapped[$key] = ConvertTo-HashtableSafe -Value $Value[$key]
        }
        return $mapped
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $list = @()
        foreach ($item in $Value) {
            $list += ,(ConvertTo-HashtableSafe -Value $item)
        }
        return $list
    }
    if ($Value -is [pscustomobject]) {
        $mapped = @{}
        foreach ($prop in $Value.PSObject.Properties) {
            $mapped[$prop.Name] = ConvertTo-HashtableSafe -Value $prop.Value
        }
        return $mapped
    }
    return $Value
}

function To-Int {
    param($Value, [int]$Default = 0)
    try {
        return [int]$Value
    } catch {
        return $Default
    }
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

function Test-TcpPortOpen {
    param(
        [string]$Host = "127.0.0.1",
        [int]$TargetPort,
        [int]$TimeoutMs = 250
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($Host, $TargetPort, $null, $null)
        $completed = $async.AsyncWaitHandle.WaitOne($TimeoutMs)
        if (-not $completed) {
            return $false
        }
        $client.EndConnect($async) | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function New-RandomSessionCode {
    param(
        [System.Collections.IDictionary]$ExistingCodes
    )

    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    for ($attempt = 0; $attempt -lt 128; $attempt++) {
        $code = ""
        for ($i = 0; $i -lt 6; $i++) {
            $code += $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)]
        }
        if (-not $ExistingCodes.Contains($code)) {
            return $code
        }
    }
    throw "failed_to_generate_unique_session_code"
}

function Send-Json {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        $Payload
    )

    $json = ConvertTo-Json -InputObject $Payload -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = "application/json"
    $Context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
    $Context.Response.ContentLength64 = $bytes.LongLength
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.OutputStream.Close()
}

function Read-RequestJson {
    param([System.Net.HttpListenerRequest]$Request)

    if (-not $Request.HasEntityBody) {
        return @{}
    }

    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    $raw = $reader.ReadToEnd()
    $reader.Close()

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{}
    }

    $parsed = $raw | ConvertFrom-Json
    return ConvertTo-HashtableSafe -Value $parsed
}

$staleAfter = [Math]::Max(3, $StaleAfterSeconds)
$instances = @{}

if (-not [string]::IsNullOrWhiteSpace($SpawnGodotExe)) {
    $SpawnGodotExe = (Resolve-Path $SpawnGodotExe).Path
}
if (-not [string]::IsNullOrWhiteSpace($SpawnProjectPath)) {
    $SpawnProjectPath = (Resolve-Path $SpawnProjectPath).Path
}
if ([string]::IsNullOrWhiteSpace($SpawnRegistryUrl)) {
    $SpawnRegistryUrl = "http://${BindHost}:$Port"
}
if ([string]::IsNullOrWhiteSpace($SpawnLogDir)) {
    if (-not [string]::IsNullOrWhiteSpace($SpawnProjectPath)) {
        $SpawnLogDir = $SpawnProjectPath
    } else {
        $SpawnLogDir = (Get-Location).Path
    }
}
if (-not [System.IO.Path]::IsPathRooted($SpawnLogDir)) {
    $SpawnLogDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $SpawnLogDir))
}
$spawnAllocatorEnabled = (-not [string]::IsNullOrWhiteSpace($SpawnGodotExe)) -and (-not [string]::IsNullOrWhiteSpace($SpawnProjectPath))

function Purge-Stale {
    $now = Get-NowUnix
    $stale = @()
    foreach ($entry in $instances.GetEnumerator()) {
        $lastSeen = To-Int $entry.Value.last_seen_unix 0
        if (($now - $lastSeen) -gt $staleAfter) {
            $stale += $entry.Key
        }
    }
    foreach ($instanceId in $stale) {
        $instances.Remove($instanceId) | Out-Null
    }
}

function New-RecordFromPayload {
    param($Payload)

    $instanceId = [string](Get-Field -Object $Payload -Name "instance_id" -Default "")
    $sessionCode = ([string](Get-Field -Object $Payload -Name "session_code" -Default "")).Trim().ToUpperInvariant()
    $host = [string](Get-Field -Object $Payload -Name "host" -Default "")
    $port = To-Int (Get-Field -Object $Payload -Name "port" -Default 0) 0
    $maxPlayers = [Math]::Max(1, (To-Int (Get-Field -Object $Payload -Name "max_players" -Default 1) 1))
    $currentPlayers = [Math]::Max(0, (To-Int (Get-Field -Object $Payload -Name "current_players" -Default 0) 0))
    $state = [string](Get-Field -Object $Payload -Name "state" -Default "LOBBY")
    if ([string]::IsNullOrWhiteSpace($state)) {
        $state = "LOBBY"
    }
    $startedUnix = To-Int (Get-Field -Object $Payload -Name "started_unix" -Default (Get-NowUnix)) (Get-NowUnix)

    if ([string]::IsNullOrWhiteSpace($instanceId) -or [string]::IsNullOrWhiteSpace($sessionCode) -or [string]::IsNullOrWhiteSpace($host) -or $port -le 0) {
        throw "instance_id, session_code, host, and port are required"
    }

    return @{
        instance_id = $instanceId.Trim()
        session_code = $sessionCode
        host = $host.Trim()
        port = $port
        max_players = $maxPlayers
        current_players = $currentPlayers
        state = $state.Trim()
        started_unix = $startedUnix
        last_seen_unix = (Get-NowUnix)
    }
}

function Resolve-SpawnPort {
    param(
        [int]$BasePort,
        [int]$SearchCount,
        [System.Collections.IDictionary]$UsedPorts
    )

    $safeBasePort = [Math]::Max(1, $BasePort)
    $safeSearchCount = [Math]::Max(1, $SearchCount)
    for ($offset = 0; $offset -lt $safeSearchCount; $offset++) {
        $candidate = $safeBasePort + $offset
        if ($candidate -gt 65535) {
            break
        }
        if ($UsedPorts.Contains($candidate)) {
            continue
        }
        if (Test-TcpPortAvailable -CandidatePort $candidate) {
            return $candidate
        }
    }
    throw "no_free_ports"
}

function Start-AllocatedLobbyInstance {
    param(
        [int]$MaxPlayers,
        [System.Collections.IDictionary]$ExistingCodes,
        [System.Collections.IDictionary]$UsedPorts
    )

    if (-not $spawnAllocatorEnabled) {
        throw "allocator_unavailable"
    }

    $sessionCode = New-RandomSessionCode -ExistingCodes $ExistingCodes
    $instanceId = "inst_{0}_{1}" -f ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()), (Get-Random -Minimum 1000 -Maximum 9999)
    $resolvedPort = Resolve-SpawnPort -BasePort $SpawnBasePort -SearchCount $SpawnPortSearchCount -UsedPorts $UsedPorts
    $startedUnix = Get-NowUnix

    [System.IO.Directory]::CreateDirectory($SpawnLogDir) | Out-Null
    $engineLog = Join-Path $SpawnLogDir ("{0}_engine.log" -f $instanceId)
    $gameplayLog = Join-Path $SpawnLogDir ("{0}.log" -f $instanceId)

    $argList = @(
        "--headless",
        "--path", $SpawnProjectPath,
        "--log-file", $engineLog,
        "--",
        "--dedicated_server",
        "--port=$resolvedPort",
        "--max_players=$MaxPlayers",
        "--start_in_run=false",
        "--server_log_interval_ms=$SpawnServerLogIntervalMs",
        "--dedicated_log_file=$gameplayLog",
        "--registry_url=$SpawnRegistryUrl",
        "--public_host=$SpawnPublicHost",
        "--session_code=$sessionCode",
        "--instance_id=$instanceId",
        "--empty_shutdown_seconds=$SpawnEmptyShutdownSeconds"
    )

    $proc = Start-Process `
        -FilePath $SpawnGodotExe `
        -ArgumentList $argList `
        -WorkingDirectory $SpawnProjectPath `
        -PassThru

    Start-Sleep -Milliseconds 200
    $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($null -eq $alive) {
        throw "spawned_instance_exited_early"
    }

    # ENet binds UDP, so we rely on "still alive shortly after spawn" instead of TCP probing.
    $followupDelayMs = [int]([Math]::Max(100, [Math]::Min(2000, [Math]::Round($SpawnReadyTimeoutSeconds * 100.0))))
    Start-Sleep -Milliseconds $followupDelayMs
    $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($null -eq $alive) {
        throw "spawned_instance_exited_early"
    }

    return @{
        instance_id = $instanceId
        session_code = $sessionCode
        host = $SpawnPublicHost
        port = $resolvedPort
        max_players = $MaxPlayers
        current_players = 0
        state = "LOBBY"
        started_unix = $startedUnix
        last_seen_unix = (Get-NowUnix)
        process_id = $proc.Id
    }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://${BindHost}:$Port/")
$listener.Start()

Write-Host ("Instance registry (PowerShell) listening on http://{0}:{1} (stale_after={2}s, allocator={3})" -f $BindHost, $Port, $staleAfter, ($(if ($spawnAllocatorEnabled) { "enabled" } else { "disabled" })))
if ($spawnAllocatorEnabled) {
    Write-Host ("Allocator config: public_host={0} base_port={1} search={2} project={3}" -f $SpawnPublicHost, $SpawnBasePort, $SpawnPortSearchCount, $SpawnProjectPath)
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $path = $request.Url.AbsolutePath
        $method = $request.HttpMethod.ToUpperInvariant()

        try {
            if ($method -eq "GET" -and $path -eq "/health") {
                Send-Json -Context $context -StatusCode 200 -Payload @{
                    ok = $true
                    status = "healthy"
                }
                continue
            }

            if ($method -eq "GET" -and $path -eq "/v1/instances/list") {
                Purge-Stale
                $rows = @($instances.Values | Sort-Object session_code, instance_id)
                Send-Json -Context $context -StatusCode 200 -Payload @{
                    ok = $true
                    count = $rows.Count
                    instances = $rows
                }
                continue
            }

            if ($method -eq "GET" -and $path -eq "/v1/instances/resolve") {
                $code = ([string]$request.QueryString["code"]).Trim().ToUpperInvariant()
                if ([string]::IsNullOrWhiteSpace($code)) {
                    Send-Json -Context $context -StatusCode 400 -Payload @{
                        ok = $false
                        error = "code query param is required"
                    }
                    continue
                }

                Purge-Stale
                $matches = @(
                    $instances.Values | Where-Object {
                        $_.session_code -eq $code -and [int]$_.current_players -lt [int]$_.max_players
                    } | Sort-Object current_players, @{ Expression = { $_.last_seen_unix }; Descending = $true }
                )

                if ($matches.Count -le 0) {
                    Send-Json -Context $context -StatusCode 404 -Payload @{
                        ok = $false
                        error = "not_found"
                    }
                    continue
                }

                $picked = $matches[0]
                Send-Json -Context $context -StatusCode 200 -Payload @{
                    ok = $true
                    session_code = $code
                    instance = $picked
                    join = @{
                        host = $picked.host
                        port = $picked.port
                    }
                }
                continue
            }

            if ($method -eq "POST" -and ($path -eq "/v1/instances/register" -or $path -eq "/v1/instances/heartbeat" -or $path -eq "/v1/instances/unregister" -or $path -eq "/v1/lobbies/create")) {
                try {
                    $payload = Read-RequestJson -Request $request
                } catch {
                    Send-Json -Context $context -StatusCode 400 -Payload @{
                        ok = $false
                        error = "invalid_json"
                    }
                    continue
                }

                Purge-Stale

                if ($path -eq "/v1/instances/register") {
                    try {
                        $record = New-RecordFromPayload -Payload $payload
                    } catch {
                        Send-Json -Context $context -StatusCode 400 -Payload @{
                            ok = $false
                            error = $_.Exception.Message
                        }
                        continue
                    }

                    $instances[$record.instance_id] = $record
                    Send-Json -Context $context -StatusCode 200 -Payload @{
                        ok = $true
                        record = $record
                    }
                    continue
                }

                if ($path -eq "/v1/instances/heartbeat") {
                    $instanceId = ([string](Get-Field -Object $payload -Name "instance_id" -Default "")).Trim()
                    if ([string]::IsNullOrWhiteSpace($instanceId)) {
                        Send-Json -Context $context -StatusCode 400 -Payload @{
                            ok = $false
                            error = "instance_id is required"
                        }
                        continue
                    }

                    if (-not $instances.Contains($instanceId)) {
                        Send-Json -Context $context -StatusCode 404 -Payload @{
                            ok = $false
                            error = "unknown_instance"
                        }
                        continue
                    }

                    $record = $instances[$instanceId]
                    if (Has-Field -Object $payload -Name "current_players") {
                        $record.current_players = [Math]::Max(0, (To-Int (Get-Field -Object $payload -Name "current_players" -Default $record.current_players) $record.current_players))
                    }
                    if (Has-Field -Object $payload -Name "max_players") {
                        $record.max_players = [Math]::Max(1, (To-Int (Get-Field -Object $payload -Name "max_players" -Default $record.max_players) $record.max_players))
                    }
                    if (Has-Field -Object $payload -Name "state") {
                        $state = ([string](Get-Field -Object $payload -Name "state" -Default $record.state)).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($state)) {
                            $record.state = $state
                        }
                    }
                    if (Has-Field -Object $payload -Name "session_code") {
                        $code = ([string](Get-Field -Object $payload -Name "session_code" -Default $record.session_code)).Trim().ToUpperInvariant()
                        if (-not [string]::IsNullOrWhiteSpace($code)) {
                            $record.session_code = $code
                        }
                    }
                    $record.last_seen_unix = (Get-NowUnix)
                    $instances[$instanceId] = $record

                    Send-Json -Context $context -StatusCode 200 -Payload @{
                        ok = $true
                        record = $record
                    }
                    continue
                }

                if ($path -eq "/v1/instances/unregister") {
                    $instanceId = ([string](Get-Field -Object $payload -Name "instance_id" -Default "")).Trim()
                    if ([string]::IsNullOrWhiteSpace($instanceId)) {
                        Send-Json -Context $context -StatusCode 400 -Payload @{
                            ok = $false
                            error = "instance_id is required"
                        }
                        continue
                    }

                    $removed = $instances.Contains($instanceId)
                    $instances.Remove($instanceId) | Out-Null
                    Send-Json -Context $context -StatusCode 200 -Payload @{
                        ok = $true
                        removed = $removed
                    }
                    continue
                }

                if ($path -eq "/v1/lobbies/create") {
                    if ([bool](Get-Field -Object $payload -Name "dry_run" -Default $false)) {
                        Send-Json -Context $context -StatusCode 200 -Payload @{
                            ok = $true
                            dry_run = $true
                            supports_create_lobby = $true
                        }
                        continue
                    }
                    if (-not $spawnAllocatorEnabled) {
                        Send-Json -Context $context -StatusCode 503 -Payload @{
                            ok = $false
                            error = "allocator_unavailable"
                        }
                        continue
                    }

                    $requestedPlayers = [Math]::Max(1, (To-Int (Get-Field -Object $payload -Name "max_players" -Default $SpawnDefaultMaxPlayers) $SpawnDefaultMaxPlayers))
                    $existingCodes = @{}
                    $usedPorts = @{}
                    foreach ($row in $instances.Values) {
                        $existingCodes[[string]$row.session_code] = $true
                        $usedPorts[[int]$row.port] = $true
                    }

                    try {
                        $record = Start-AllocatedLobbyInstance -MaxPlayers $requestedPlayers -ExistingCodes $existingCodes -UsedPorts $usedPorts
                    } catch {
                        $errorText = $_.Exception.Message
                        $statusCode = if ($errorText -eq "allocator_unavailable") { 503 } else { 500 }
                        Send-Json -Context $context -StatusCode $statusCode -Payload @{
                            ok = $false
                            error = $errorText
                        }
                        continue
                    }

                    $instances[$record.instance_id] = $record
                    Send-Json -Context $context -StatusCode 200 -Payload @{
                        ok = $true
                        created = $true
                        session_code = $record.session_code
                        instance = $record
                        join = @{
                            host = $record.host
                            port = $record.port
                        }
                    }
                    continue
                }
            }

            Send-Json -Context $context -StatusCode 404 -Payload @{
                ok = $false
                error = "not_found"
            }
        } catch {
            Send-Json -Context $context -StatusCode 500 -Payload @{
                ok = $false
                error = "internal_error"
                detail = $_.Exception.Message
            }
        }
    }
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
