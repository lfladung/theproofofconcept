extends RefCounted
class_name DungeonMapLayoutV1

const DOOR_WIDTH_TILES := 4
const CARDINALS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]


static func generate(rng: RandomNumberGenerator, config: Dictionary = {}) -> Dictionary:
	var total_min := int(config.get("total_rooms_min", 8))
	var total_max := int(config.get("total_rooms_max", 10))
	var critical_min := int(config.get("critical_path_min", 5))
	var critical_max := int(config.get("critical_path_max", 8))
	var max_attempts := int(config.get("max_attempts", 32))

	for _attempt in range(max_attempts):
		var stage1 := _stage1_generate_graph(rng, total_min, total_max, critical_min, critical_max)
		if not bool(stage1.get("ok", false)):
			continue
		var stage2 := _stage2_validate_graph(stage1, total_min, total_max, critical_min, critical_max)
		if not bool(stage2.get("ok", false)):
			continue
		var stage3 := _stage3_assign_roles(stage1, stage2, rng)
		var stage4 := _stage4_place_spatial(stage1, stage2, rng)
		if not bool(stage4.get("ok", false)):
			continue
		var stage5 := _stage5_validate_spatial(stage1, stage2, stage4)
		if not bool(stage5.get("ok", false)):
			continue
		var stage6 := _stage6_generate_layout(stage1, stage2, stage3, stage4)
		var stage7 := _stage7_final_validate(stage6)
		if not bool(stage7.get("ok", false)):
			continue
		return {
			"ok": true,
			"stage_debug": {
				"graph": stage1,
				"graph_validation": stage2,
				"roles": stage3,
				"spatial": stage4,
				"spatial_validation": stage5,
				"generated": stage6,
				"final": stage7,
			},
		}.merged(stage6)
	return {
		"ok": false,
		"error": "Could not generate a valid linear-spine dungeon after retries.",
	}


static func _stage1_generate_graph(
	rng: RandomNumberGenerator,
	total_min: int,
	total_max: int,
	critical_min: int,
	critical_max: int
) -> Dictionary:
	var total := rng.randi_range(total_min, total_max)
	# Keep side branches off interior nodes excluding the one right before exit so exit is strictly furthest.
	var min_cp_for_sides := int(ceili(float(total + 3) * 0.5))
	var cp_low := maxi(critical_min, min_cp_for_sides)
	# Must have >= 1 side room so treasure can always be an optional dead-end branch.
	var cp_high := mini(critical_max, total - 1)
	if cp_low > cp_high:
		return {"ok": false}
	var cp_len := rng.randi_range(cp_low, cp_high)
	var nodes: Array[String] = []
	var critical_path: Array[String] = []
	for i in range(cp_len):
		var id := "CP_%02d" % i
		nodes.append(id)
		critical_path.append(id)
	var edges: Array[Dictionary] = []
	for i in range(cp_len - 1):
		edges.append({"a": critical_path[i], "b": critical_path[i + 1]})

	var side_count := total - cp_len
	var attach_candidates: Array[String] = []
	for i in range(1, cp_len - 2):
		attach_candidates.append(critical_path[i])
	attach_candidates.shuffle()
	if side_count > attach_candidates.size():
		return {"ok": false}
	var side_branches: Array[Array] = []
	for i in range(side_count):
		var parent := attach_candidates[i]
		var sid := "SB_%02d" % i
		nodes.append(sid)
		edges.append({"a": parent, "b": sid})
		side_branches.append([parent, sid])
	return {
		"ok": true,
		"nodes": nodes,
		"edges": edges,
		"start_room": critical_path[0],
		"exit_room": critical_path[cp_len - 1],
		"critical_path": critical_path,
		"side_branches": side_branches,
	}


static func _stage2_validate_graph(
	stage1: Dictionary,
	total_min: int,
	total_max: int,
	critical_min: int,
	critical_max: int
) -> Dictionary:
	var nodes := stage1.get("nodes", []) as Array
	var edges := stage1.get("edges", []) as Array
	var start_room := String(stage1.get("start_room", ""))
	var exit_room := String(stage1.get("exit_room", ""))
	var adj := _adjacency(nodes, edges)

	if nodes.is_empty() or start_room.is_empty() or exit_room.is_empty():
		return {"ok": false, "error": "Missing nodes/start/exit."}
	if nodes.size() < total_min or nodes.size() > total_max:
		return {"ok": false, "error": "Total room count out of bounds."}
	if nodes.size() <= 1:
		return {"ok": false, "error": "Graph too small."}
	if edges.size() != nodes.size() - 1:
		return {"ok": false, "error": "Graph must be a tree (edge count mismatch)."}
	if not _is_connected(start_room, nodes, adj):
		return {"ok": false, "error": "Graph is disconnected."}

	var path := _path_between(start_room, exit_room, adj)
	if path.is_empty():
		return {"ok": false, "error": "No start->exit path."}
	if path.size() < critical_min or path.size() > critical_max:
		return {"ok": false, "error": "Critical path length out of bounds."}
	if _count_paths(start_room, exit_room, adj, 2) != 1:
		return {"ok": false, "error": "Multiple start->exit paths found."}
	var dist := _bfs_distances(start_room, adj)
	var exit_dist := int(dist.get(exit_room, -1))
	for n in nodes:
		var id := String(n)
		if id == exit_room:
			continue
		if int(dist.get(id, -1)) >= exit_dist:
			return {"ok": false, "error": "Exit room must be strictly furthest from start."}

	var path_set: Dictionary = {}
	for n in path:
		path_set[n] = true
	var side_count := 0
	for n in nodes:
		var id := String(n)
		var deg := (adj.get(id, []) as Array).size()
		if path_set.has(id):
			if deg > 3:
				return {"ok": false, "error": "Critical node degree exceeds 3."}
		else:
			side_count += 1
			if deg != 1:
				return {"ok": false, "error": "Side room must be a dead-end (degree 1)."}
	if side_count < 1:
		return {"ok": false, "error": "At least one side dead-end branch is required."}
	return {
		"ok": true,
		"critical_path": path,
	}


static func _stage3_assign_roles(stage1: Dictionary, stage2: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var path := stage2.get("critical_path", []) as Array
	var roles: Dictionary = {}
	if path.is_empty():
		return {"roles": roles}
	roles[path[0]] = "start"
	roles[path[path.size() - 1]] = "exit"
	var puzzle_idx := clampi(path.size() - 3, 1, path.size() - 2)
	var trap_idx := clampi(2, 1, path.size() - 2)
	for i in range(1, path.size() - 1):
		var node := String(path[i])
		if i == puzzle_idx:
			roles[node] = "puzzle"
		elif i == trap_idx and i != puzzle_idx and rng.randf() < 0.35:
			roles[node] = "trap"
		else:
			roles[node] = "combat"

	var path_set: Dictionary = {}
	for p in path:
		path_set[p] = true
	var side_nodes: Array[String] = []
	for n in stage1.get("nodes", []) as Array:
		var id := String(n)
		if not path_set.has(id):
			side_nodes.append(id)
	side_nodes.shuffle()
	if not side_nodes.is_empty():
		roles[side_nodes[0]] = "treasure"
	for i in range(1, side_nodes.size()):
		roles[side_nodes[i]] = "safe"

	var puzzle_room := String(path[puzzle_idx])
	var next_room := String(path[puzzle_idx + 1])
	return {
		"roles": roles,
		"puzzle_room": puzzle_room,
		"puzzle_next_room": next_room,
	}


static func _stage4_place_spatial(stage1: Dictionary, stage2: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var path := stage2.get("critical_path", []) as Array
	if path.is_empty():
		return {"ok": false, "error": "Missing critical path."}
	var pos: Dictionary = {}
	for i in range(path.size()):
		pos[String(path[i])] = Vector2i(i, 0)

	var adj := _adjacency(stage1.get("nodes", []) as Array, stage1.get("edges", []) as Array)
	var path_set: Dictionary = {}
	for p in path:
		path_set[p] = true
	for n in stage1.get("nodes", []) as Array:
		var id := String(n)
		if path_set.has(id):
			continue
		var neigh := adj.get(id, []) as Array
		if neigh.is_empty():
			return {"ok": false, "error": "Unattached side node."}
		var parent := String(neigh[0])
		var ppos := pos.get(parent, Vector2i.ZERO) as Vector2i
		var dirs := CARDINALS.duplicate()
		dirs.shuffle()
		var placed := false
		for d in dirs:
			var v := d as Vector2i
			var cand := ppos + v
			if not _position_taken(pos, cand):
				pos[id] = cand
				placed = true
				break
		if not placed:
			return {"ok": false, "error": "Could not place side node without overlap."}
	return {"ok": true, "positions": pos}


static func _stage5_validate_spatial(stage1: Dictionary, stage2: Dictionary, stage4: Dictionary) -> Dictionary:
	var pos := stage4.get("positions", {}) as Dictionary
	var edges := stage1.get("edges", []) as Array
	if pos.size() != (stage1.get("nodes", []) as Array).size():
		return {"ok": false, "error": "Unplaced nodes detected."}
	for e in edges:
		var a := String(e.get("a", ""))
		var b := String(e.get("b", ""))
		var pa := pos.get(a, Vector2i.ZERO) as Vector2i
		var pb := pos.get(b, Vector2i.ZERO) as Vector2i
		if abs(pa.x - pb.x) + abs(pa.y - pb.y) != 1:
			return {"ok": false, "error": "Non-cardinal or non-adjacent connection in layout."}
	var critical := stage2.get("critical_path", []) as Array
	var prev_x := -99999
	for node in critical:
		var p := pos.get(String(node), Vector2i.ZERO) as Vector2i
		if p.x <= prev_x:
			return {"ok": false, "error": "Critical path readability failed (non-forward placement)."}
		prev_x = p.x
	return {"ok": true}


static func _stage6_generate_layout(
	stage1: Dictionary,
	stage2: Dictionary,
	stage3: Dictionary,
	stage4: Dictionary
) -> Dictionary:
	var nodes := stage1.get("nodes", []) as Array
	var edges := stage1.get("edges", []) as Array
	var roles := stage3.get("roles", {}) as Dictionary
	var pos := stage4.get("positions", {}) as Dictionary
	var room_specs: Array[Dictionary] = []
	var combat_rooms: Array[String] = []
	var treasure_rooms: Array[String] = []
	var trap_rooms: Array[String] = []
	for n in nodes:
		var id := String(n)
		var kind := String(roles.get(id, "combat"))
		var size := _size_for_kind(kind)
		room_specs.append({
			"name": id,
			"kind": kind,
			"size": size,
			"grid": pos.get(id, Vector2i.ZERO),
		})
		if kind == "combat":
			combat_rooms.append(id)
		elif kind == "treasure":
			treasure_rooms.append(id)
		elif kind == "trap":
			trap_rooms.append(id)

	var links: Array[Dictionary] = []
	for e in edges:
		var a := String(e.get("a", ""))
		var b := String(e.get("b", ""))
		var pa := pos.get(a, Vector2i.ZERO) as Vector2i
		var pb := pos.get(b, Vector2i.ZERO) as Vector2i
		var dir := pb - pa
		links.append({
			"from": a,
			"to": b,
			"from_dir": _dir_from_delta(dir),
			"to_dir": _dir_from_delta(-dir),
		})

	var critical := stage2.get("critical_path", []) as Array
	var puzzle_room := String(stage3.get("puzzle_room", ""))
	var puzzle_next := String(stage3.get("puzzle_next_room", ""))
	var puzzle_gate_dir := "east"
	if not puzzle_room.is_empty() and not puzzle_next.is_empty():
		var pr := pos.get(puzzle_room, Vector2i.ZERO) as Vector2i
		var pn := pos.get(puzzle_next, Vector2i.ZERO) as Vector2i
		puzzle_gate_dir = _dir_from_delta(pn - pr)

	var combat_room := combat_rooms[0] if not combat_rooms.is_empty() else String(critical[maxi(1, critical.size() - 2)])
	var ci := maxi(1, critical.find(combat_room))
	var combat_entry := String(critical[ci - 1])
	var combat_exit := String(critical[mini(critical.size() - 1, ci + 1)])
	var cpos := pos.get(combat_room, Vector2i.ZERO) as Vector2i
	var combat_entry_dir := _dir_from_delta((pos.get(combat_entry, Vector2i.ZERO) as Vector2i) - cpos)
	var combat_exit_dir := _dir_from_delta((pos.get(combat_exit, Vector2i.ZERO) as Vector2i) - cpos)

	var exit_room := String(stage1.get("exit_room", ""))
	var exit_idx := critical.find(exit_room)
	var before_exit := String(critical[maxi(0, exit_idx - 1)])
	var boss_entry_dir := _dir_from_delta((pos.get(before_exit, Vector2i.ZERO) as Vector2i) - (pos.get(exit_room, Vector2i.ZERO) as Vector2i))

	return {
		"room_specs": room_specs,
		"links": links,
		"start_room": String(stage1.get("start_room", "")),
		"exit_room": exit_room,
		"critical_path": critical,
		"side_branches": stage1.get("side_branches", []),
		"combat_rooms": combat_rooms,
		"combat_room": combat_room,
		"treasure_rooms": treasure_rooms,
		"trap_rooms": trap_rooms,
		"treasure_room": treasure_rooms[0] if not treasure_rooms.is_empty() else "",
		"trap_room": trap_rooms[0] if not trap_rooms.is_empty() else "",
		"puzzle_room": puzzle_room,
		"puzzle_gate_dir": puzzle_gate_dir,
		"combat_entry_dir": combat_entry_dir,
		"combat_exit_dir": combat_exit_dir,
		"boss_entry_dir": boss_entry_dir,
	}


static func _stage7_final_validate(layout: Dictionary) -> Dictionary:
	var links := layout.get("links", []) as Array
	var room_specs := layout.get("room_specs", []) as Array
	var nodes: Array[String] = []
	for spec in room_specs:
		if spec is Dictionary:
			nodes.append(String((spec as Dictionary).get("name", "")))
	var adj := _adjacency(nodes, _edges_from_links(links))
	var start_room := String(layout.get("start_room", ""))
	var exit_room := String(layout.get("exit_room", ""))
	if not _is_connected(start_room, nodes, adj):
		return {"ok": false, "error": "Final dungeon disconnected."}
	if _count_paths(start_room, exit_room, adj, 2) != 1:
		return {"ok": false, "error": "Final dungeon has invalid critical-path multiplicity."}

	var critical := layout.get("critical_path", []) as Array
	var critical_set: Dictionary = {}
	for c in critical:
		critical_set[c] = true
	for n in nodes:
		if critical_set.has(n):
			continue
		if (adj.get(n, []) as Array).size() != 1:
			return {"ok": false, "error": "Side room is not optional dead-end."}
	return {"ok": true}


static func adjacency_from_links(links: Array) -> Dictionary:
	var adj: Dictionary = {}
	for link in links:
		var a := String(link.get("from", ""))
		var b := String(link.get("to", ""))
		var da := String(link.get("from_dir", ""))
		var db := String(link.get("to_dir", ""))
		if a.is_empty() or b.is_empty() or da.is_empty() or db.is_empty():
			continue
		if not adj.has(a):
			adj[a] = {}
		if not adj.has(b):
			adj[b] = {}
		(adj[a] as Dictionary)[da] = DOOR_WIDTH_TILES
		(adj[b] as Dictionary)[db] = DOOR_WIDTH_TILES
	return adj


static func kind_to_room_type(kind: String) -> String:
	match kind:
		"start":
			return "safe"
		"exit":
			return "boss"
		"combat":
			return "arena"
		"puzzle":
			return "puzzle"
		"treasure":
			return "treasure"
		"trap":
			return "trap"
		"challenge":
			return "arena"
		"lore":
			return "safe"
		_:
			return "connector"


static func _adjacency(nodes: Array, edges: Array) -> Dictionary:
	var adj: Dictionary = {}
	for n in nodes:
		adj[String(n)] = []
	for e in edges:
		var a := String(e.get("a", ""))
		var b := String(e.get("b", ""))
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	return adj


static func _is_connected(start_room: String, nodes: Array, adj: Dictionary) -> bool:
	if start_room.is_empty():
		return false
	var seen: Dictionary = {}
	var q: Array[String] = [start_room]
	while not q.is_empty():
		var cur := String(q.pop_front())
		if seen.has(cur):
			continue
		seen[cur] = true
		for n in adj.get(cur, []) as Array:
			var nx := String(n)
			if not seen.has(nx):
				q.append(nx)
	return seen.size() == nodes.size()


static func _bfs_distances(start_room: String, adj: Dictionary) -> Dictionary:
	var dist: Dictionary = {start_room: 0}
	var q: Array[String] = [start_room]
	while not q.is_empty():
		var cur := String(q.pop_front())
		var base := int(dist.get(cur, 0))
		for n in adj.get(cur, []) as Array:
			var nx := String(n)
			if dist.has(nx):
				continue
			dist[nx] = base + 1
			q.append(nx)
	return dist


static func _path_between(start_room: String, exit_room: String, adj: Dictionary) -> Array[String]:
	var prev: Dictionary = {}
	var q: Array[String] = [start_room]
	var seen: Dictionary = {start_room: true}
	while not q.is_empty():
		var cur := String(q.pop_front())
		if cur == exit_room:
			break
		for n in adj.get(cur, []) as Array:
			var nx := String(n)
			if seen.has(nx):
				continue
			seen[nx] = true
			prev[nx] = cur
			q.append(nx)
	if not seen.has(exit_room):
		return []
	var path: Array[String] = []
	var at := exit_room
	while at != "":
		path.push_front(at)
		at = String(prev.get(at, ""))
	return path


static func _count_paths(start_room: String, exit_room: String, adj: Dictionary, cap: int) -> int:
	var seen: Dictionary = {}
	return _dfs_count_paths(start_room, exit_room, adj, seen, cap)


static func _dfs_count_paths(cur: String, target: String, adj: Dictionary, seen: Dictionary, cap: int) -> int:
	if cap <= 0:
		return cap
	if cur == target:
		return 1
	seen[cur] = true
	var total := 0
	for n in adj.get(cur, []) as Array:
		var nx := String(n)
		if seen.has(nx):
			continue
		total += _dfs_count_paths(nx, target, adj, seen, cap - total)
		if total >= cap:
			seen.erase(cur)
			return total
	seen.erase(cur)
	return total


static func _position_taken(pos: Dictionary, p: Vector2i) -> bool:
	for k in pos.keys():
		if (pos[k] as Vector2i) == p:
			return true
	return false


static func _dir_from_delta(d: Vector2i) -> String:
	if d == Vector2i(1, 0):
		return "east"
	if d == Vector2i(-1, 0):
		return "west"
	if d == Vector2i(0, 1):
		return "south"
	if d == Vector2i(0, -1):
		return "north"
	return "east"


static func _size_for_kind(kind: String) -> Vector2i:
	match kind:
		"start":
			return Vector2i(12, 12)
		"exit":
			return Vector2i(15, 12)
		"combat":
			return Vector2i(12, 12)
		"puzzle":
			return Vector2i(12, 12)
		"treasure":
			return Vector2i(9, 9)
		"trap":
			return Vector2i(9, 9)
		_:
			return Vector2i(9, 9)


static func _edges_from_links(links: Array) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for link in links:
		edges.append({"a": String(link.get("from", "")), "b": String(link.get("to", ""))})
	return edges
