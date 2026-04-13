#!/usr/bin/env python3
"""Lightweight in-memory instance directory with optional lobby allocation.

Endpoints:
- GET  /health
- GET  /v1/instances/list
- GET  /v1/instances/resolve?code=ABC123
- POST /v1/instances/register
- POST /v1/instances/heartbeat
- POST /v1/instances/unregister
- POST /v1/lobbies/create
"""

from __future__ import annotations

import argparse
import json
import os
import random
import socket
import string
import subprocess
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse


LOBBY_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
LOBBY_CODE_LENGTH = 6
HUB_MAX_PLAYERS = 6
RUN_MAX_PLAYERS = 4
INSTANCE_KIND_HUB = "hub"
INSTANCE_KIND_RUN = "run"


@dataclass
class InstanceRecord:
    instance_id: str
    session_code: str
    host: str
    port: int
    max_players: int
    current_players: int
    state: str
    started_unix: int
    last_seen_unix: int
    process_id: int = 0
    kind: str = INSTANCE_KIND_HUB
    mission_id: str = ""

    def to_json(self) -> dict[str, Any]:
        return {
            "instance_id": self.instance_id,
            "session_code": self.session_code,
            "host": self.host,
            "port": self.port,
            "max_players": self.max_players,
            "current_players": self.current_players,
            "state": self.state,
            "started_unix": self.started_unix,
            "last_seen_unix": self.last_seen_unix,
            "process_id": self.process_id,
            "kind": self.kind,
            "mission_id": self.mission_id,
        }


@dataclass
class PartyMemberRecord:
    member_id: str
    ready: bool
    joined_unix: int
    last_seen_unix: int

    def to_json(self) -> dict[str, Any]:
        return {
            "member_id": self.member_id,
            "ready": self.ready,
            "joined_unix": self.joined_unix,
            "last_seen_unix": self.last_seen_unix,
        }


@dataclass
class PartyRecord:
    party_code: str
    owner_member_id: str
    mission_id: str
    max_players: int
    created_unix: int
    last_seen_unix: int
    members: dict[str, PartyMemberRecord]
    launch: dict[str, Any] | None = None

    def to_json(self) -> dict[str, Any]:
        return {
            "party_code": self.party_code,
            "owner_member_id": self.owner_member_id,
            "mission_id": self.mission_id,
            "max_players": self.max_players,
            "created_unix": self.created_unix,
            "last_seen_unix": self.last_seen_unix,
            "members": [member.to_json() for member in self.members.values()],
            "launch": self.launch or {},
        }


@dataclass
class SpawnConfig:
    godot_exe: str
    project_path: str
    registry_url: str
    public_host: str
    base_port: int
    port_search_count: int
    default_max_players: int
    server_log_interval_ms: int
    empty_shutdown_seconds: int
    ready_timeout_seconds: float
    log_dir: str


class DedicatedInstanceSpawner:
    def __init__(self, config: SpawnConfig) -> None:
        self._cfg = config

    @staticmethod
    def _now() -> int:
        return int(time.time())

    def _random_session_code(self, used_codes: set[str]) -> str:
        for _ in range(128):
            code = "".join(random.choice(LOBBY_CODE_CHARS) for _ in range(LOBBY_CODE_LENGTH))
            if code not in used_codes:
                return code
        raise RuntimeError("failed_to_generate_unique_session_code")

    def _build_instance_id(self) -> str:
        millis = int(time.time() * 1000)
        suffix = "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(4))
        return f"inst_{millis}_{suffix}"

    @staticmethod
    def _is_port_available(port: int) -> bool:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.bind(("0.0.0.0", port))
            return True
        except OSError:
            return False
        finally:
            sock.close()

    def _pick_port(self, used_ports: set[int]) -> int:
        start = max(1, self._cfg.base_port)
        for offset in range(max(1, self._cfg.port_search_count)):
            candidate = start + offset
            if candidate > 65535:
                break
            if candidate in used_ports:
                continue
            if self._is_port_available(candidate):
                return candidate
        raise RuntimeError("no_free_ports")

    def spawn_instance(
        self,
        *,
        requested_max_players: int,
        used_ports: set[int],
        used_codes: set[str],
        instance_kind: str = INSTANCE_KIND_HUB,
        mission_id: str = "",
    ) -> dict[str, Any]:
        max_players = max(1, requested_max_players or self._cfg.default_max_players)
        normalized_kind = instance_kind.strip().lower() or INSTANCE_KIND_HUB
        normalized_mission_id = mission_id.strip()
        session_code = self._random_session_code(used_codes)
        instance_id = self._build_instance_id()
        port = self._pick_port(used_ports)
        started_unix = self._now()

        os.makedirs(self._cfg.log_dir, exist_ok=True)
        engine_log = os.path.join(self._cfg.log_dir, f"{instance_id}_engine.log")
        gameplay_log = os.path.join(self._cfg.log_dir, f"{instance_id}.log")

        args = [
            self._cfg.godot_exe,
            "--headless",
            "--path",
            self._cfg.project_path,
            "--log-file",
            engine_log,
            "--",
            "--dedicated_server",
            f"--port={port}",
            f"--max_players={max_players}",
            f"--start_in_run={'true' if normalized_kind == INSTANCE_KIND_RUN else 'false'}",
            f"--server_log_interval_ms={self._cfg.server_log_interval_ms}",
            f"--dedicated_log_file={gameplay_log}",
            f"--registry_url={self._cfg.registry_url}",
            f"--public_host={self._cfg.public_host}",
            f"--session_code={session_code}",
            f"--instance_id={instance_id}",
            f"--instance_kind={normalized_kind}",
            f"--empty_shutdown_seconds={self._cfg.empty_shutdown_seconds}",
        ]
        if normalized_mission_id:
            args.append(f"--mission_id={normalized_mission_id}")

        process = subprocess.Popen(
            args,
            cwd=self._cfg.project_path,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        time.sleep(0.2)
        if process.poll() is not None:
            raise RuntimeError("spawned_instance_exited_early")
        # ENet uses UDP; there is no cheap universal TCP readiness probe.
        time.sleep(max(0.1, min(2.0, self._cfg.ready_timeout_seconds * 0.1)))
        if process.poll() is not None:
            raise RuntimeError("spawned_instance_exited_early")

        return {
            "instance_id": instance_id,
            "session_code": session_code,
            "host": self._cfg.public_host,
            "port": port,
            "max_players": max_players,
            "current_players": 0,
            "state": "IN_RUN" if normalized_kind == INSTANCE_KIND_RUN else "LOBBY",
            "started_unix": started_unix,
            "process_id": int(process.pid),
            "kind": normalized_kind,
            "mission_id": normalized_mission_id,
        }


class InstanceDirectory:
    def __init__(self, stale_after_seconds: int, spawner: DedicatedInstanceSpawner | None) -> None:
        self._stale_after = stale_after_seconds
        self._spawner = spawner
        self._lock = threading.Lock()
        self._instances: dict[str, InstanceRecord] = {}
        self._parties: dict[str, PartyRecord] = {}

    def _now(self) -> int:
        return int(time.time())

    def _purge_stale_locked(self) -> None:
        now = self._now()
        stale_ids = [
            instance_id
            for instance_id, record in self._instances.items()
            if (now - int(record.last_seen_unix)) > self._stale_after
        ]
        for instance_id in stale_ids:
            del self._instances[instance_id]
        stale_party_codes = [
            party_code
            for party_code, party in self._parties.items()
            if (now - int(party.last_seen_unix)) > self._stale_after
        ]
        for party_code in stale_party_codes:
            del self._parties[party_code]

    def register(self, payload: dict[str, Any]) -> dict[str, Any]:
        instance_id = str(payload.get("instance_id", "")).strip()
        session_code = str(payload.get("session_code", "")).strip().upper()
        host = str(payload.get("host", "")).strip()
        port = int(payload.get("port", 0))
        max_players = int(payload.get("max_players", 0))
        current_players = int(payload.get("current_players", 0))
        state = str(payload.get("state", "LOBBY")).strip() or "LOBBY"
        started_unix = int(payload.get("started_unix", self._now()))
        process_id = int(payload.get("process_id", 0))
        kind = str(payload.get("kind", INSTANCE_KIND_HUB)).strip().lower() or INSTANCE_KIND_HUB
        mission_id = str(payload.get("mission_id", "")).strip()

        if not instance_id or not session_code or not host or port <= 0:
            raise ValueError("instance_id, session_code, host, and port are required")

        record = InstanceRecord(
            instance_id=instance_id,
            session_code=session_code,
            host=host,
            port=port,
            max_players=max(1, max_players),
            current_players=max(0, current_players),
            state=state,
            started_unix=started_unix,
            last_seen_unix=self._now(),
            process_id=max(0, process_id),
            kind=kind,
            mission_id=mission_id,
        )

        with self._lock:
            self._purge_stale_locked()
            self._instances[instance_id] = record

        return {"ok": True, "record": record.to_json()}

    def heartbeat(self, payload: dict[str, Any]) -> dict[str, Any]:
        instance_id = str(payload.get("instance_id", "")).strip()
        if not instance_id:
            raise ValueError("instance_id is required")

        with self._lock:
            self._purge_stale_locked()
            record = self._instances.get(instance_id)
            if record is None:
                return {"ok": False, "error": "unknown_instance"}

            if "current_players" in payload:
                record.current_players = max(0, int(payload.get("current_players", record.current_players)))
            if "max_players" in payload:
                record.max_players = max(1, int(payload.get("max_players", record.max_players)))
            if "state" in payload:
                state = str(payload.get("state", record.state)).strip()
                record.state = state if state else record.state
            if "session_code" in payload:
                code = str(payload.get("session_code", record.session_code)).strip().upper()
                record.session_code = code if code else record.session_code
            if "host" in payload:
                host = str(payload.get("host", record.host)).strip()
                record.host = host if host else record.host
            if "port" in payload:
                port = int(payload.get("port", record.port))
                record.port = port if port > 0 else record.port
            if "process_id" in payload:
                record.process_id = max(0, int(payload.get("process_id", record.process_id)))
            if "kind" in payload:
                kind = str(payload.get("kind", record.kind)).strip().lower()
                record.kind = kind if kind else record.kind
            if "mission_id" in payload:
                mission_id = str(payload.get("mission_id", record.mission_id)).strip()
                record.mission_id = mission_id if mission_id else record.mission_id

            record.last_seen_unix = self._now()
            self._instances[instance_id] = record
            return {"ok": True, "record": record.to_json()}

    def unregister(self, payload: dict[str, Any]) -> dict[str, Any]:
        instance_id = str(payload.get("instance_id", "")).strip()
        if not instance_id:
            raise ValueError("instance_id is required")

        with self._lock:
            self._purge_stale_locked()
            existed = instance_id in self._instances
            self._instances.pop(instance_id, None)

        return {"ok": True, "removed": existed}

    def resolve(self, session_code: str) -> dict[str, Any]:
        code = session_code.strip().upper()
        if not code:
            raise ValueError("code query param is required")

        with self._lock:
            self._purge_stale_locked()
            matches = [
                record
                for record in self._instances.values()
                if record.session_code == code and record.current_players < record.max_players
            ]

            if not matches:
                return {"ok": False, "error": "not_found"}

            matches.sort(key=lambda r: (r.current_players, -r.last_seen_unix))
            record = matches[0]
            return {
                "ok": True,
                "session_code": code,
                "instance": record.to_json(),
                "join": {
                    "host": record.host,
                    "port": record.port,
                },
            }

    def create_lobby(self, payload: dict[str, Any]) -> dict[str, Any]:
        if bool(payload.get("dry_run", False)):
            return {"ok": True, "dry_run": True, "supports_create_lobby": True}
        return self.allocate_hub(payload)

    def allocate_hub(self, payload: dict[str, Any]) -> dict[str, Any]:
        if bool(payload.get("dry_run", False)):
            return {"ok": True, "dry_run": True, "supports_create_lobby": True, "supports_hub_allocation": True}
        if self._spawner is None:
            return {"ok": False, "error": "allocator_unavailable"}
        requested_max_players = int(payload.get("max_players", HUB_MAX_PLAYERS))

        with self._lock:
            self._purge_stale_locked()
            candidates = [
                record
                for record in self._instances.values()
                if record.kind == INSTANCE_KIND_HUB
                and record.state == "LOBBY"
                and record.current_players < min(record.max_players, requested_max_players)
            ]
            if candidates:
                candidates.sort(key=lambda r: (-r.current_players, -r.last_seen_unix))
                record = candidates[0]
                record.current_players = min(record.max_players, record.current_players + 1)
                record.last_seen_unix = self._now()
                return {
                    "ok": True,
                    "created": False,
                    "session_code": record.session_code,
                    "instance": record.to_json(),
                    "join": {
                        "host": record.host,
                        "port": record.port,
                    },
                }
            used_ports = {int(row.port) for row in self._instances.values()}
            used_codes = {str(row.session_code).upper() for row in self._instances.values()}
            spawn = self._spawner.spawn_instance(
                requested_max_players=requested_max_players,
                used_ports=used_ports,
                used_codes=used_codes,
                instance_kind=INSTANCE_KIND_HUB,
            )
            record = InstanceRecord(
                instance_id=str(spawn["instance_id"]),
                session_code=str(spawn["session_code"]),
                host=str(spawn["host"]),
                port=int(spawn["port"]),
                max_players=max(1, int(spawn["max_players"])),
                current_players=max(0, int(spawn["current_players"])),
                state=str(spawn["state"]).strip() or "LOBBY",
                started_unix=int(spawn["started_unix"]),
                last_seen_unix=self._now(),
                process_id=max(0, int(spawn.get("process_id", 0))),
                kind=str(spawn.get("kind", INSTANCE_KIND_HUB)),
                mission_id=str(spawn.get("mission_id", "")),
            )
            record.current_players = min(record.max_players, record.current_players + 1)
            self._instances[record.instance_id] = record

        return {
            "ok": True,
            "created": True,
            "session_code": record.session_code,
            "instance": record.to_json(),
            "join": {
                "host": record.host,
                "port": record.port,
            },
        }

    def create_party(self, payload: dict[str, Any]) -> dict[str, Any]:
        mission_id = str(payload.get("mission_id", "")).strip()
        owner_member_id = str(payload.get("member_id", "")).strip()
        if not mission_id or not owner_member_id:
            raise ValueError("mission_id and member_id are required")
        with self._lock:
            self._purge_stale_locked()
            used_codes = set(self._parties.keys())
            party_code = self._random_party_code(used_codes)
            now = self._now()
            member = PartyMemberRecord(
                member_id=owner_member_id,
                ready=False,
                joined_unix=now,
                last_seen_unix=now,
            )
            party = PartyRecord(
                party_code=party_code,
                owner_member_id=owner_member_id,
                mission_id=mission_id,
                max_players=RUN_MAX_PLAYERS,
                created_unix=now,
                last_seen_unix=now,
                members={owner_member_id: member},
            )
            self._parties[party_code] = party
            return {"ok": True, "party": party.to_json()}

    def join_party(self, payload: dict[str, Any]) -> dict[str, Any]:
        party_code = str(payload.get("party_code", "")).strip().upper()
        member_id = str(payload.get("member_id", "")).strip()
        if not party_code or not member_id:
            raise ValueError("party_code and member_id are required")
        with self._lock:
            self._purge_stale_locked()
            party = self._parties.get(party_code)
            if party is None:
                return {"ok": False, "error": "party_not_found"}
            if member_id not in party.members and len(party.members) >= party.max_players:
                return {"ok": False, "error": "party_full"}
            now = self._now()
            party.members[member_id] = PartyMemberRecord(
                member_id=member_id,
                ready=False,
                joined_unix=now,
                last_seen_unix=now,
            )
            party.last_seen_unix = now
            return {"ok": True, "party": party.to_json()}

    def update_party_member(self, payload: dict[str, Any]) -> dict[str, Any]:
        party_code = str(payload.get("party_code", "")).strip().upper()
        member_id = str(payload.get("member_id", "")).strip()
        if not party_code or not member_id:
            raise ValueError("party_code and member_id are required")
        with self._lock:
            self._purge_stale_locked()
            party = self._parties.get(party_code)
            if party is None:
                return {"ok": False, "error": "party_not_found"}
            member = party.members.get(member_id)
            if member is None:
                return {"ok": False, "error": "member_not_found"}
            if "ready" in payload:
                member.ready = bool(payload.get("ready", member.ready))
            if party.owner_member_id == member_id and "mission_id" in payload:
                mission_id = str(payload.get("mission_id", party.mission_id)).strip()
                party.mission_id = mission_id if mission_id else party.mission_id
            member.last_seen_unix = self._now()
            party.last_seen_unix = member.last_seen_unix
            return {"ok": True, "party": party.to_json()}

    def leave_party(self, payload: dict[str, Any]) -> dict[str, Any]:
        party_code = str(payload.get("party_code", "")).strip().upper()
        member_id = str(payload.get("member_id", "")).strip()
        if not party_code or not member_id:
            raise ValueError("party_code and member_id are required")
        with self._lock:
            self._purge_stale_locked()
            party = self._parties.get(party_code)
            if party is None:
                return {"ok": True, "removed": False}
            party.members.pop(member_id, None)
            if not party.members or party.owner_member_id == member_id:
                self._parties.pop(party_code, None)
                return {"ok": True, "removed": True}
            party.last_seen_unix = self._now()
            return {"ok": True, "removed": True, "party": party.to_json()}

    def get_party_snapshot(self, party_code: str, member_id: str = "") -> dict[str, Any]:
        code = party_code.strip().upper()
        if not code:
            raise ValueError("party_code is required")
        with self._lock:
            self._purge_stale_locked()
            party = self._parties.get(code)
            if party is None:
                return {"ok": False, "error": "party_not_found"}
            if member_id and member_id in party.members:
                party.members[member_id].last_seen_unix = self._now()
                party.last_seen_unix = party.members[member_id].last_seen_unix
            return {"ok": True, "party": party.to_json()}

    def start_party_run(self, payload: dict[str, Any]) -> dict[str, Any]:
        party_code = str(payload.get("party_code", "")).strip().upper()
        member_id = str(payload.get("member_id", "")).strip()
        if not party_code or not member_id:
            raise ValueError("party_code and member_id are required")
        with self._lock:
            self._purge_stale_locked()
            party = self._parties.get(party_code)
            if party is None:
                return {"ok": False, "error": "party_not_found"}
            if party.owner_member_id != member_id:
                return {"ok": False, "error": "not_party_owner"}
            if not party.mission_id:
                return {"ok": False, "error": "mission_required"}
            for member in party.members.values():
                if not member.ready:
                    return {"ok": False, "error": "party_not_ready"}
            if party.launch:
                return {"ok": True, "party": party.to_json(), "launch": party.launch}
            if self._spawner is None:
                return {"ok": False, "error": "allocator_unavailable"}
            used_ports = {int(row.port) for row in self._instances.values()}
            used_codes = {str(row.session_code).upper() for row in self._instances.values()}
            spawn = self._spawner.spawn_instance(
                requested_max_players=RUN_MAX_PLAYERS,
                used_ports=used_ports,
                used_codes=used_codes,
                instance_kind=INSTANCE_KIND_RUN,
                mission_id=party.mission_id,
            )
            record = InstanceRecord(
                instance_id=str(spawn["instance_id"]),
                session_code=str(spawn["session_code"]),
                host=str(spawn["host"]),
                port=int(spawn["port"]),
                max_players=max(1, int(spawn["max_players"])),
                current_players=max(0, int(spawn["current_players"])),
                state=str(spawn["state"]).strip() or "IN_RUN",
                started_unix=int(spawn["started_unix"]),
                last_seen_unix=self._now(),
                process_id=max(0, int(spawn.get("process_id", 0))),
                kind=INSTANCE_KIND_RUN,
                mission_id=party.mission_id,
            )
            self._instances[record.instance_id] = record
            party.launch = {
                "instance": record.to_json(),
                "join": {
                    "host": record.host,
                    "port": record.port,
                },
            }
            party.last_seen_unix = self._now()
            return {"ok": True, "party": party.to_json(), "launch": party.launch}

    def _random_party_code(self, used_codes: set[str]) -> str:
        return self._spawner._random_session_code(used_codes) if self._spawner is not None else self._fallback_random_code(used_codes)

    def _fallback_random_code(self, used_codes: set[str]) -> str:
        for _ in range(128):
            code = "".join(random.choice(LOBBY_CODE_CHARS) for _ in range(LOBBY_CODE_LENGTH))
            if code not in used_codes:
                return code
        raise RuntimeError("failed_to_generate_unique_party_code")

    def list_instances(self) -> dict[str, Any]:
        with self._lock:
            self._purge_stale_locked()
            rows = [record.to_json() for record in self._instances.values()]

        rows.sort(key=lambda r: (r["session_code"], r["instance_id"]))
        return {"ok": True, "count": len(rows), "instances": rows}


class RequestHandler(BaseHTTPRequestHandler):
    directory: InstanceDirectory

    def _send_json(self, code: int, payload: dict[str, Any]) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._send_json(200, {"ok": True, "status": "healthy"})
            return
        if parsed.path == "/v1/instances/list":
            self._send_json(200, self.directory.list_instances())
            return
        if parsed.path == "/v1/instances/resolve":
            query = parse_qs(parsed.query)
            code = str((query.get("code") or [""])[0])
            try:
                result = self.directory.resolve(code)
            except ValueError as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
                return
            status = 200 if result.get("ok") else 404
            self._send_json(status, result)
            return
        if parsed.path == "/v1/parties/snapshot":
            query = parse_qs(parsed.query)
            code = str((query.get("code") or [""])[0])
            member_id = str((query.get("member_id") or [""])[0])
            try:
                result = self.directory.get_party_snapshot(code, member_id)
            except ValueError as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
                return
            status = 200 if result.get("ok") else 404
            self._send_json(status, result)
            return

        self._send_json(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        try:
            payload = self._read_json()
        except json.JSONDecodeError:
            self._send_json(400, {"ok": False, "error": "invalid_json"})
            return

        try:
            if parsed.path == "/v1/instances/register":
                self._send_json(200, self.directory.register(payload))
                return
            if parsed.path == "/v1/instances/heartbeat":
                result = self.directory.heartbeat(payload)
                status = 200 if result.get("ok") else 404
                self._send_json(status, result)
                return
            if parsed.path == "/v1/instances/unregister":
                self._send_json(200, self.directory.unregister(payload))
                return
            if parsed.path == "/v1/lobbies/create":
                result = self.directory.create_lobby(payload)
                if result.get("ok"):
                    self._send_json(200, result)
                    return
                error = str(result.get("error", "allocator_error"))
                if error == "allocator_unavailable":
                    self._send_json(503, result)
                    return
                self._send_json(500, result)
                return
            if parsed.path == "/v1/hubs/join":
                result = self.directory.allocate_hub(payload)
                if result.get("ok"):
                    self._send_json(200, result)
                    return
                error = str(result.get("error", "allocator_error"))
                self._send_json(503 if error == "allocator_unavailable" else 500, result)
                return
            if parsed.path == "/v1/parties/create":
                self._send_json(200, self.directory.create_party(payload))
                return
            if parsed.path == "/v1/parties/join":
                result = self.directory.join_party(payload)
                status = 200 if result.get("ok") else 409 if result.get("error") == "party_full" else 404
                self._send_json(status, result)
                return
            if parsed.path == "/v1/parties/update":
                result = self.directory.update_party_member(payload)
                status = 200 if result.get("ok") else 404
                self._send_json(status, result)
                return
            if parsed.path == "/v1/parties/leave":
                self._send_json(200, self.directory.leave_party(payload))
                return
            if parsed.path == "/v1/parties/start":
                result = self.directory.start_party_run(payload)
                status = 200 if result.get("ok") else 409
                self._send_json(status, result)
                return
        except ValueError as exc:
            self._send_json(400, {"ok": False, "error": str(exc)})
            return
        except RuntimeError as exc:
            self._send_json(500, {"ok": False, "error": str(exc)})
            return

        self._send_json(404, {"ok": False, "error": "not_found"})

    def log_message(self, fmt: str, *args: Any) -> None:
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        msg = fmt % args
        print(f"[{stamp}] {self.address_string()} {msg}")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Instance registry for dedicated co-op runs")
    parser.add_argument("--host", default="127.0.0.1", help="bind host")
    parser.add_argument("--port", type=int, default=8787, help="bind port")
    parser.add_argument(
        "--stale-after-seconds",
        type=int,
        default=20,
        help="remove instances that miss heartbeat for this many seconds",
    )

    # Optional lobby allocation/spawn support.
    parser.add_argument("--spawn-godot-exe", default="", help="path to Godot console/headless executable")
    parser.add_argument("--spawn-project-path", default="", help="path to Godot project root")
    parser.add_argument("--spawn-registry-url", default="", help="registry base URL used by spawned instances")
    parser.add_argument("--spawn-public-host", default="127.0.0.1", help="public host clients connect to")
    parser.add_argument("--spawn-base-port", type=int, default=7000, help="first port to probe for new instances")
    parser.add_argument(
        "--spawn-port-search-count",
        type=int,
        default=500,
        help="number of sequential ports to probe for free port allocation",
    )
    parser.add_argument("--spawn-default-max-players", type=int, default=HUB_MAX_PLAYERS, help="default hub max players")
    parser.add_argument(
        "--spawn-server-log-interval-ms",
        type=int,
        default=1500,
        help="server heartbeat/diag log interval for spawned instances",
    )
    parser.add_argument(
        "--spawn-empty-shutdown-seconds",
        type=int,
        default=20,
        help="shutdown spawned dedicated instance after this many empty seconds",
    )
    parser.add_argument(
        "--spawn-ready-timeout-seconds",
        type=float,
        default=8.0,
        help="how long allocator waits for spawned instance to begin listening",
    )
    parser.add_argument("--spawn-log-dir", default="", help="directory for spawned instance logs")
    return parser


def build_spawner(args: argparse.Namespace) -> DedicatedInstanceSpawner | None:
    godot_exe = str(args.spawn_godot_exe).strip()
    project_path = str(args.spawn_project_path).strip()
    if not godot_exe or not project_path:
        return None
    if not os.path.isfile(godot_exe):
        raise RuntimeError(f"spawn-godot-exe not found: {godot_exe}")
    if not os.path.isdir(project_path):
        raise RuntimeError(f"spawn-project-path not found: {project_path}")

    registry_url = str(args.spawn_registry_url).strip()
    if not registry_url:
        registry_url = f"http://{args.host}:{args.port}"

    log_dir = str(args.spawn_log_dir).strip()
    if not log_dir:
        log_dir = project_path

    cfg = SpawnConfig(
        godot_exe=os.path.abspath(godot_exe),
        project_path=os.path.abspath(project_path),
        registry_url=registry_url,
        public_host=str(args.spawn_public_host).strip() or "127.0.0.1",
        base_port=max(1, int(args.spawn_base_port)),
        port_search_count=max(1, int(args.spawn_port_search_count)),
        default_max_players=max(1, int(args.spawn_default_max_players)),
        server_log_interval_ms=max(200, int(args.spawn_server_log_interval_ms)),
        empty_shutdown_seconds=max(5, int(args.spawn_empty_shutdown_seconds)),
        ready_timeout_seconds=max(0.5, float(args.spawn_ready_timeout_seconds)),
        log_dir=os.path.abspath(log_dir),
    )
    return DedicatedInstanceSpawner(cfg)


def main() -> None:
    args = build_arg_parser().parse_args()
    spawner = build_spawner(args)
    directory = InstanceDirectory(
        stale_after_seconds=max(3, args.stale_after_seconds),
        spawner=spawner,
    )

    handler_cls = RequestHandler
    handler_cls.directory = directory

    server = ThreadingHTTPServer((args.host, args.port), handler_cls)
    spawn_status = "enabled" if spawner is not None else "disabled"
    print(
        "Instance registry listening on http://%s:%s (stale_after=%ss, allocator=%s)"
        % (args.host, args.port, max(3, args.stale_after_seconds), spawn_status)
    )
    if spawner is not None:
        print(
            "Allocator config: public_host=%s base_port=%s search=%s project=%s"
            % (
                spawner._cfg.public_host,
                spawner._cfg.base_port,
                spawner._cfg.port_search_count,
                spawner._cfg.project_path,
            )
        )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
