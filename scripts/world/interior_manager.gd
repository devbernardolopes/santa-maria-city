class_name InteriorManager
extends Node
## Loads one interior at a far-away origin while the exterior keeps simulating.

signal interior_entered(interior: Interior)
signal interior_exited()

## Interiors live here on the same canvas, far outside the imported map (which starts near x = 1700 m).
const INTERIOR_ORIGIN_M: Vector2 = Vector2(-10000.0, 0.0)
const FADE_DURATION_S: float = 0.2
const RETURN_OFFSET_M: float = 1.0
const ROOM_SCALE: float = 0.6
const MIN_ROOM_SIZE_M: Vector2 = Vector2(5.0, 4.0)
const MAX_ROOM_SIZE_M: Vector2 = Vector2(14.0, 10.0)

## The manager in the current scene; Interactables reach it through this.
static var active: InteriorManager = null

var _interiors: Node2D = null
var _fader: ScreenFader = null
var _camera: FollowCamera = null
var _day_night: DayNight = null
var _map: MapLoader = null

var _transitioning: bool = false
var _inside: bool = false
var _current_interior: Interior = null
var _return_point_m: Vector2 = Vector2.ZERO
var _saved_day_night: bool = true


func _ready() -> void:
	var world: Node = get_parent()
	_interiors = world.get_node_or_null("Interiors") as Node2D
	_fader = world.get_node_or_null("ScreenFader") as ScreenFader
	_camera = world.get_node_or_null("FollowCamera") as FollowCamera
	_day_night = world.get_node_or_null("DayNight") as DayNight
	_map = world.get_node_or_null("Map") as MapLoader
	active = self
	if not _is_configured():
		push_error(
			"InteriorManager: missing Interiors, ScreenFader, FollowCamera, or DayNight sibling; "
			+ "interiors are disabled."
		)


func _exit_tree() -> void:
	if active == self:
		active = null


func is_inside() -> bool:
	return _inside


## Moves the actor into the entrance's interior. Ignored during transitions or while inside.
func enter(entrance: Entrance, actor: Entity) -> void:
	if _transitioning or _inside or not _is_configured():
		return
	if entrance == null or not is_instance_valid(entrance) or actor == null or not is_instance_valid(actor):
		return
	_transitioning = true
	actor.set_locked(true)
	await _fader.fade_out(FADE_DURATION_S)
	if not is_instance_valid(actor):
		push_warning("InteriorManager: the actor was freed during the enter transition.")
		await _finish_failed_transition(null)
		return
	var interior: Interior = _instantiate_interior(entrance)
	if interior == null:
		push_warning("InteriorManager: could not create an interior for entrance '%s'." % entrance.data.id)
		await _finish_failed_transition(actor)
		return
	interior.position = Units.to_px(INTERIOR_ORIGIN_M)
	_interiors.add_child(interior)
	_current_interior = interior
	_return_point_m = entrance.get("position_m") + entrance.get("normal") * RETURN_OFFSET_M
	actor.global_position = interior.get_entry_point_global()
	_camera.set_limits_m(_global_bounds_m(interior))
	_camera.snap_to_target()
	_saved_day_night = _day_night.enabled
	_day_night.enabled = false
	interior.exit_requested.connect(_on_exit_requested)
	_inside = true
	await _fader.fade_in(FADE_DURATION_S)
	if is_instance_valid(actor):
		actor.set_locked(false)
	_transitioning = false
	interior_entered.emit(interior)


## Returns the actor to one meter in front of the entrance that was used. Ignored when not inside.
func exit(actor: Entity) -> void:
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
		actor.global_position = Units.to_px(_return_point_m)
		_camera.snap_to_target()
	else:
		push_warning("InteriorManager: the actor was freed during the exit transition.")
	await _fader.fade_in(FADE_DURATION_S)
	if is_instance_valid(actor):
		actor.set_locked(false)
	_transitioning = false
	interior_exited.emit()


func _on_exit_requested(actor: Entity) -> void:
	exit(actor)


func _finish_failed_transition(actor: Entity) -> void:
	await _fader.fade_in(FADE_DURATION_S)
	if actor != null and is_instance_valid(actor):
		actor.set_locked(false)
	_transitioning = false


func _free_interior() -> void:
	if _current_interior != null and is_instance_valid(_current_interior):
		_current_interior.free()
	_current_interior = null


## Authored scene at res://scenes/interiors/<id>.tscn, else a placeholder sized from the footprint.
func _instantiate_interior(entrance: Node) -> Node:
	var source: Resource = entrance.get("data")
	if source != null and not source.get("interior_id").is_empty():
		var interior_id: String = source.get("interior_id")
		var path: String = "res://scenes/interiors/%s.tscn" % interior_id
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			var node: Node = scene.instantiate() if scene != null else null
			if node != null and node.is_class("Interior"):
				return node
			push_warning("InteriorManager: %s must have an Interior root; using the placeholder." % path)
			if node != null:
				node.free()
		else:
			push_warning("InteriorManager: no scene at %s; using the placeholder." % path)
	return _placeholder_interior(entrance)


func _placeholder_interior(entrance: Node) -> Node:
	var placeholder: Node = load("res://scripts/world/placeholder_interior.gd").new()
	var source: Resource = entrance.get("data")
	var ring: PackedVector2Array = PackedVector2Array()
	if source != null and _map != null:
		var building_id: String = source.get("building_osm_id")
		ring = _map.get_building_ring_m(building_id)
		var label: String = source.get("label")
		if placeholder.has_method("set"):
			if not label.is_empty():
				placeholder.set("room_label", label)
			else:
				placeholder.set("room_label", building_id)
		var geom: Script = preload("res://scripts/world/building_geometry.gd")
		var size: Vector2 = geom.call("bounding_size_m", ring) * ROOM_SCALE
		size.x = clampf(size.x, MIN_ROOM_SIZE_M.x, MAX_ROOM_SIZE_M.x)
		size.y = clampf(size.y, MIN_ROOM_SIZE_M.y, MAX_ROOM_SIZE_M.y)
		placeholder.set("room_size_m", size)
	return placeholder


func _global_bounds_m(interior: Interior) -> Rect2:
	var bounds: Rect2 = interior.get_bounds_m()
	return Rect2(INTERIOR_ORIGIN_M + bounds.position, bounds.size)


func _is_configured() -> bool:
	return _interiors != null and _fader != null and _camera != null and _day_night != null
