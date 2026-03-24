extends Object
class_name HitboxOverlap2D

## World-space convex polygon for a mob's primary CollisionShape2D (circle → N-gon, rectangle → quad).
static func mob_collision_polygon_world(mob: CharacterBody2D) -> PackedVector2Array:
	if mob == null:
		return PackedVector2Array()
	var cs := mob.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return PackedVector2Array()
	var sh := cs.shape
	if sh is CircleShape2D:
		var circ := sh as CircleShape2D
		var r := circ.radius * _max_abs_scale(cs.global_transform.get_scale())
		return _circle_to_polygon(cs.global_position, r, 20)
	if sh is RectangleShape2D:
		return _rect_shape_polygon(cs, sh as RectangleShape2D)
	return PackedVector2Array()


static func _max_abs_scale(s: Vector2) -> float:
	return maxf(absf(s.x), absf(s.y))


static func _circle_to_polygon(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if segments < 3 or radius <= 0.0:
		return pts
	for i in range(segments):
		var ang: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
	return pts


static func _rect_shape_polygon(cs: CollisionShape2D, rect: RectangleShape2D) -> PackedVector2Array:
	var xf := cs.global_transform
	var hs := rect.size * 0.5
	var pts := PackedVector2Array()
	for c in [Vector2(-hs.x, -hs.y), Vector2(hs.x, -hs.y), Vector2(hs.x, hs.y), Vector2(-hs.x, hs.y)]:
		pts.append(xf * c)
	return pts


static func convex_polygons_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false
	var inter := Geometry2D.intersect_polygons(a, b)
	return inter.size() > 0


static func circle_overlaps_polygon(center: Vector2, radius: float, poly: PackedVector2Array) -> bool:
	if poly.size() < 3 or radius < 0.0:
		return false
	if Geometry2D.is_point_in_polygon(center, poly):
		return true
	var n := poly.size()
	for i in range(n):
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % n]
		var closest := Geometry2D.get_closest_point_to_segment(center, p0, p1)
		if center.distance_to(closest) <= radius:
			return true
	return false
