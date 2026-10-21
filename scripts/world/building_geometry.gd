class_name BuildingGeometry
extends RefCounted
## Pure geometry helpers on building footprints, in meters.

const OUTWARD_PROBE_M: float = 0.2
const MIN_EDGE_LENGTH_SQ: float = 0.000001


## Closest point on the ring's edges plus the outward unit normal of that edge.
## Returns {"position": Vector2, "normal": Vector2}; the normal is Vector2.ZERO for a degenerate ring.
static func snap_to_edge(ring_m: PackedVector2Array, point_m: Vector2) -> Dictionary:
	if ring_m.size() < 2:
		return {"position": point_m, "normal": Vector2.ZERO}
	var best_point: Vector2 = point_m
	var best_normal: Vector2 = Vector2.ZERO
	var best_distance: float = INF
	for index: int in range(ring_m.size()):
		var a: Vector2 = ring_m[index]
		var b: Vector2 = ring_m[(index + 1) % ring_m.size()]
		var edge: Vector2 = b - a
		if edge.length_squared() <= MIN_EDGE_LENGTH_SQ:
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point_m, a, b)
		var distance: float = point_m.distance_squared_to(closest)
		if distance >= best_distance:
			continue
		best_distance = distance
		best_point = closest
		var normal: Vector2 = edge.orthogonal().normalized()
		if Geometry2D.is_point_in_polygon(closest + normal * OUTWARD_PROBE_M, ring_m):
			normal = -normal
		best_normal = normal
	return {"position": best_point, "normal": best_normal}


## Width x height of the ring's axis-aligned bounding box.
static func bounding_size_m(ring_m: PackedVector2Array) -> Vector2:
	if ring_m.is_empty():
		return Vector2.ZERO
	var bounds := Rect2(ring_m[0], Vector2.ZERO)
	for point: Vector2 in ring_m:
		bounds = bounds.expand(point)
	return bounds.size
