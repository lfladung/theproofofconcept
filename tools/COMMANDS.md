# One-Command Launchers

Run these from repo root (`C:\git\dungeonGame\dungeonGameConvertToMultplayer`).

## Start Session Allocator (Recommended)

```powershell
.\tools\start_dedicated_server.ps1
```

This starts the session allocator (registry + on-demand dedicated instance spawning).
Players can host/join using only session codes.

The dedicated launcher waits up to 30 seconds for registry health by default. Override if needed:

```powershell
.\tools\start_dedicated_server.ps1 -RegistryReadyTimeoutSeconds 60
```

Set allocator networking options:

```powershell
.\tools\start_dedicated_server.ps1 -RegistryUrl http://127.0.0.1:8787 -PublicHost 127.0.0.1 -Port 7000
```

To launch one fixed dedicated server manually (legacy/debug only):

```powershell
.\tools\start_dedicated_server.ps1 -LaunchBootstrapInstance:$true -Detached
```

Use desktop executable instead of console (not recommended for server runs):

```powershell
.\tools\start_dedicated_server.ps1 -UseDesktopExe
```

Default logs:
- Registry stdout (if auto-started): `instance_registry.log`
- Registry stderr (if auto-started): `instance_registry.log.err`
- Spawned game instances: `inst_*.log` and `inst_*_engine.log`

## Start Player Client

```powershell
.\tools\start_player_client.ps1
```

## Tail Dedicated Gameplay Log

```powershell
.\tools\tail_dedicated_log.ps1
```

(Wait up to 30 seconds for log file creation)

```powershell
.\tools\tail_dedicated_log.ps1 -WaitTimeoutSeconds 30
```

## Tail Engine Log

```powershell
Get-Content .\dedicated_server_engine.log -Wait
```

## Start Registry

```powershell
.\tools\start_registry.ps1
```

Normally not required anymore if you launch with `.\tools\start_dedicated_server.ps1`.
