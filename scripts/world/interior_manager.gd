class_name InteriorManager
extends Node
## In-place interior system: interiors live inside the real building footprint.

signal interior_entered(interior)
signal interior_exited

const FADE_DURATION_S: float = 0.2
const RETURN_OFFSET_M: float = 0.5

## The manager in the current scene; Interactables reach it through this.
static var active = null

var _interiors = null
var _fader = null
var _camera = null
var _day_night = null
var _map = null
var _current_entrance = null
var _transitioning = false
var _inside = false
var _current_interior = null
var _return_point_m = Vector2.ZERO
var _saved_day_night = true
var _interior_shell = null


func _ready() -> void:
	var world = get_node_or_null("/root/World") as Node2D
	if world == null:
		push_error("InteriorManager: World node not found in scene.")
		return
	_interiors = world.get_node_or_null("Interiors") as Node2D
	_fader = world.get_node_or_null("ScreenFader") as ScreenFader
	_camera = world.get_node_or_null("FollowCamera") as FollowCamera
	_day_night = world.get_node_or_null("DayNight") as DayNight
	_map = world.get_node_or_null("Map") as MapLoader
	active = self
	if not _is_configured():
		push_error(
			(
				"InteriorManager: missing Interiors, ScreenFader, FollowCamera, or DayNight sibling; "
				+ "interiors are disabled."
			)
		)


func _exit_tree() -> void:
	if active == self:
		active = null


func is_inside() -> bool:
	return _inside


func enter(entrance, actor) -> void:
	if _transitioning or _inside or not _is_configured():
		return
	if (
		entrance == null
		or not is_instance_valid(entrance)
		or actor == null
		or not is_instance_valid(actor)
	):
		return
	_transitioning = true
	actor.set_locked(true)
	await _fader.fade_out(FADE_DURATION_S)
	if not is_instance_valid(actor):
		push_warning("InteriorManager: the actor was freed during the enter transition.")
		await _finish_failed_transition(actor)
		return
	_current_entrance = entrance
	var interior = _instantiate_interior(entrance)
	if interior == null:
		push_warning(
			"InteriorManager: could not create an interior for entrance '%s'." % entrance.data.id
		)
		await _finish_failed_transition(actor)
		return
	# position interior at the real building footprint
	var building_id = entrance.get("data").get("building_osm_id")
	var ring_m = _map.get_building_ring_m(building_id)
	if ring_m.size() >= 3:
		var ring_px = _ring_to_px(ring_m)
		var bounds = _bounds_of(ring_px)
		interior.global_position = -bounds.position
	else:
		interior.global_position = Vector2.ZERO
	_interiors.add_child(interior)
	_current_interior = interior
	# place actor just inside the entrance, 1m from the door along the normal
	var entrance_pos_px = Units.to_px(entrance.data.position_m)
	var entrance_normal = entrance.data.normal
	var offset = entrance_normal.orthogonal() * (Units.m_to_px(RETURN_OFFSET_M))
	_return_point_m = entrance_pos_px + offset
	actor.global_position = entrance_pos_px + entrance_normal * Units.m_to_px(-0.9) + offset
	_camera.set_limits_m(interior.get_current_bounds_m())
	_camera.snap_to_target()
	_saved_day_night = _day_night.enabled
	_day_night.enabled = false
	# enable interior shell collision (thin ring around footprint)
	_enable_interior_shell(interior, ring_m)
	interior.exit_requested.connect(_on_exit_requested)
	_inside = true
	await _fader.fade_in(FADE_DURATION_S)
	if is_instance_valid(actor):
		actor.set_locked(false)
	_transitioning = false
	interior_entered.emit(interior)


func exit(actor) -> void:
	if _transitioning or not _inside or not _is_configured():
		return
	if actor == null or not is_instance_valid(actor):
		return
	_transitioning = true
	actor.set_locked(true)
	await _fader.fade_out(FADE_DURATION_S)
	_free_interior()
	_camera.clear_limits()
	_day_night.enabled = _saved_day_night
	_inside = false
	if is_instance_valid(actor):
		actor.global_position = _return_point_m
		_camera.snap_to_target()
	else:
		push_warning("InteriorManager: the actor was freed during the exit transition.")
	await _fader.fade_in(FADE_DURATION_S)
	if is_instance_valid(actor):
		actor.set_locked(false)
	_transitioning = false
	interior_exited.emit()


func _on_exit_requested(actor) -> void:
	exit(actor)


func _finish_failed_transition(actor) -> void:
	await _fader.fade_in(FADE_DURATION_S)
	if actor != null and is_instance_valid(actor):
		actor.set_locked(false)
	_transitioning = false


func _enable_interior_shell(interior, ring_m) -> void:
	if _interior_shell != null:
		_interior_shell.queue_free()
	_interior_shell = null
	if ring_m.size() < 3:
		return
	var ring_px = _ring_to_px(ring_m)
	if ring_px.size() < 3:
		return
	var offset_px = Units.m_to_px(0.2)
	var points = PackedVector2Array()
	for i in range(ring_px.size()):
		var p = ring_px[i]
		var prev = ring_px[(i - 1) % ring_px.size()]
		var next = ring_px[(i + 1) % ring_px.size()]
		var edge_in = (p - prev).normalized() + (next - p).normalized()
		if edge_in.length_squared() > 0.0:
			edge_in = edge_in.normalized()
		else:
			edge_in = Vector2.UP
		var inward = p + edge_in * offset_px
		points.append(inward)
	if points.size() >= 3:
		var poly = CollisionPolygon2D.new()
		poly.build_mode = CollisionPolygon2D.BUILD_SOLIDS
		poly.polygon = points
		poly.name = "InteriorShell"
		interior.add_child(poly)
		_interior_shell = poly


func _instantiate_interior(entrance) -> Node2D:
	var source = entrance.get("data")
	if source != null and not source.get("interior_id").is_empty():
		var interior_id = source.get("interior_id")
		var path = "res://scenes/interiors/%s.tscn" % interior_id
		if ResourceLoader.exists(path):
			var scene = load(path) as PackedScene
			var node = scene.instantiate() as Node2D
			if node != null and node.is_class("Node2D"):
				return node
			if node != null:
				node.free()
	else:
		var interior = _procedural_interior(entrance)
		return interior
	return null


func _procedural_interior(entrance) -> Node2D:
	var source = entrance.get("data")
	var building_id = source.get("building_osm_id")
	var label = source.get("label")
	var ring_m = _map.get_building_ring_m(building_id)
	var interior = Node2D.new()
	interior.name = "Interior_%s" % (label.is_empty() and building_id or label)

	if ring_m.size() >= 3:
		var ring_px = _ring_to_px(ring_m)
		var bounds = _bounds_of(ring_px)
		# Floor: solid color
		var floor = ColorRect.new()
		floor.name = "Floor"
		floor.color = Color(0.2, 0.2, 0.2)
		floor.position = Vector2.ZERO
		floor.size = bounds.size
		interior.add_child(floor)
		# Ceiling: translucent
		var ceiling = ColorRect.new()
		ceiling.name = "Ceiling"
		ceiling.color = Color(0.1, 0.1, 0.1, 0.2)
		ceiling.position = Vector2.ZERO
		ceiling.size = bounds.size
		interior.add_child(ceiling)
		# outline
		var outline = Line2D.new()
		outline.name = "Outline"
		outline.draw_mode = 0
		outline.points = ring_px
		outline.width = 2.0
		outline.color = Color(1.0, 1.0, 0.0)
		interior.add_child(outline)
		interior.set("current_bounds_m", Rect2(Vector2.ZERO, bounds.size))

	var entry_point = Marker2D.new()
	entry_point.name = "EntryPoint"
	entry_point.position = Vector2.ZERO
	interior.add_child(entry_point)

	return interior


func _ring_to_px(ring_m) -> PackedVector2Array:
	var points = PackedVector2Array()
	for point_m in ring_m:
		points.append(point_m * 16.0)
	return points


func _bounds_of(points) -> Rect2:
	var bounds = Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


func get_current_bounds_m() -> Rect2:
	if _current_interior != null and _current_interior.has_method("get_current_bounds_m"):
		return _current_interior.get_current_bounds_m()
	return Rect2()


func _free_interior() -> void:
	if _current_interior != null and is_instance_valid(_current_interior):
		_current_interior.queue_free()
	_current_interior = null
	if is_instance_valid(_interior_shell):
		_interior_shell.queue_free()
	_interior_shell = null


func _is_configured() -> bool:
	return _interiors != null and _fader != null and _camera != null and _day_night != null
