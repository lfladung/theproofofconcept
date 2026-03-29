"""
Move hall_socket_double grid_position from legacy anchors to min-corner anchors
expected by DungeonRoomGridMath.anchor_rect (tile AABB aligned with walls).

Legacy (outline generator before 2026-03): west/east (x, 0), north/south (0, y).
Target: west/east (x, -1), north/south (-1, y).

Idempotent: skips pieces that already look migrated.
"""
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
# v2 is regenerated from generate_outline_rooms.gd; only migrate archived v1 (or pass --all).
V1_ONLY = REPO / "dungeon/rooms/authored/outlines/v1"


def migrate_text(s: str) -> str:
    parts = s.split('piece_id = &"hall_socket_double"')
    if len(parts) == 1:
        return s
    out = [parts[0]]
    for chunk in parts[1:]:
        gm = re.search(r"grid_position = Vector2i\((-?\d+), (-?\d+)\)", chunk)
        rm = re.search(r"rotation_steps = (\d+)", chunk)
        if gm and rm:
            x, y = int(gm.group(1)), int(gm.group(2))
            r = int(rm.group(1)) % 4
            if r in (1, 3):
                if y == 0:
                    y -= 1
            elif r == 0:
                if x == 0:
                    x -= 1
            elif r == 2:
                if x == 0:
                    x -= 1
            newg = f"grid_position = Vector2i({x}, {y})"
            chunk = chunk[: gm.start()] + newg + chunk[gm.end() :]
        out.append('piece_id = &"hall_socket_double"' + chunk)
    return "".join(out)


def main() -> None:
    import sys

    root = V1_ONLY
    if "--all" in sys.argv:
        root = REPO / "dungeon/rooms/authored/outlines"
    for p in sorted(root.rglob("*.layout.tres")):
        old = p.read_text(encoding="utf-8")
        new = migrate_text(old)
        if new != old:
            p.write_text(new, encoding="utf-8")
            print("migrated", p.relative_to(REPO))


if __name__ == "__main__":
    main()
