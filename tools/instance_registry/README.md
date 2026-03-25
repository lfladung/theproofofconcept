# Instance Registry (Milestone 2)

Lightweight session-directory service for dedicated Godot instances.

## Run

```powershell
# Option A
python tools/instance_registry/instance_registry_server.py --host=127.0.0.1 --port=8787

# Option B (Windows launcher helper)
.\tools\instance_registry\run_registry.ps1

# Optional custom bind host/port
.\tools\instance_registry\run_registry.ps1 -BindHost 0.0.0.0 -Port 8787
```

## Endpoints

- `GET /health`
- `GET /v1/instances/list`
- `GET /v1/instances/resolve?code=ABC123`
- `POST /v1/instances/register`
- `POST /v1/instances/heartbeat`
- `POST /v1/instances/unregister`
- `POST /v1/lobbies/create` (allocates/spawns a dedicated instance and returns a new session code + join endpoint)

## Dedicated Server Launch Example

```powershell
& "C:\git\dungeonGame\dungeonGameConvertToMultplayer\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" `
  --headless --path "C:\git\dungeonGame\dungeonGameConvertToMultplayer" `
  --dedicated_server --port=7000 --max_players=4 --start_in_run=true `
  --registry_url=http://127.0.0.1:8787 `
  --public_host=127.0.0.1 --session_code=ABCD12
```

## Notes

- Registry data is in-memory only (no persistence yet).
- Allocator support requires launching registry with spawn args (handled automatically by `.\tools\start_dedicated_server.ps1`).
- Use this as the bridge to full matchmaking/instance orchestration in the next milestone.
- `session_code` is what clients/party services will use to resolve an instance endpoint.
