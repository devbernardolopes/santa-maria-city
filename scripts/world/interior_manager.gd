class_name InteriorManager
extends Node
## Interior system: one interior exists at a time, far outside the imported city so map
## collision cannot touch it.
##
## Entering locks the actor, fades out, builds the room (authored scene or placeholder),
## moves the actor to its EntryPoint and restricts the camera to the room. Exiting reverses
## all of it and returns the actor one meter in front of the door. The exterior keeps
## simulating the whole time.

signal interior_entered(interior: Interior)
signal interior_exited

const FADE_DURATION_S: float = 0.2
## Preferred distance from the door to the outside return point, in meters.
const EXIT_OFFSET_M: float = 1.0
const EXIT_OFFSET_STEPS_M: Array[float] = [1.0, 1.5, 2.0]
const ROOM_MIN_SIZE_M: Vector2 = Vector2(5.0, 4.0)
const ROOM_MAX_SIZE_M: Vector2 = Vector2(14.0, 10.0)
const INTERIOR_SCENE_FORMAT: String = "res://scenes/interiors/%s.tscn"
const FALLBACK_FOOTPRINT_SIZE_M: Vector2 = Vector2(6.0, 5.0)
## Interiors live on the same canvas, far outside the imported city, so building and water
## collision cannot touch them. Only one interior exists at a time.
const INTERIOR_ORIGIN_M: Vector2 = Vector2(-10000.0, 0.0)

## The manager in the current scene; entrances reach it through this.
static var active: InteriorManager = null

var _interiors: Node2D = null
var _fader: ScreenFader = null
var _camera: FollowCamera = null
var _day_night: DayNight = null
var _map: MapLoader = null
var _current_entrance: Entrance = null
var _current_interior: Interior = null
var _exit_point_m: Vector2 = Vector2.ZERO
var _transitioning: bool = false
var _inside: bool = false
var _saved_day_night: bool = true


func _ready() -> void:
	var world: Node = get_parent()
	if world == null:
		push_error("InteriorManager: no parent World node; interiors are disabled.")
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
				"InteriorManager: missing Interiors, ScreenFader, FollowCamera, DayNight, or Map; "
				+ "interiors are disabled."
			)
		)


func _exit_tree() -> void:
	if active == self:
		active = null


func is_inside() -> bool:
	return _inside


## True while a fade transition is covering the screen and input is locked.
func is_transitioning() -> bool:
	return _transitioning


func get_current_interior() -> Interior:
	return _current_interior


func get_current_entrance() -> Entrance:
	return _current_entrance


func enter(entrance: Entrance, actor: Entity) -> void:
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
	var footprint_m: Rect2 = _footprint_m(entrance)
	var interior: Interior = _instantiate_interior(entrance)
	if interior == null:
		push_warning("InteriorManager: could not create an interior for entrance '%s'." % entrance.name)
		await _finish_failed_transition(actor)
		return
	_configure_interior(interior, entrance, footprint_m)
	_interiors.add_child(interior)
	interior.global_position = Units.to_px(INTERIOR_ORIGIN_M)
	_current_entrance = entrance
	_current_interior = interior
	_exit_point_m = _find_exit_point_m(entrance)
	_place_actor_inside(actor, interior, footprint_m)
	_camera.set_limits_m(_camera_limits_m(interior))
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
		actor.global_position = Units.to_px(_exit_point_m)
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


## Building footprint in meters, or a small square around the door when the building is
## unknown (still enterable, just not shaped by the map).
func _footprint_m(entrance: Entrance) -> Rect2:
	var ring_m: PackedVector2Array = _map.get_building_ring_m(entrance.get_building_osm_id())
	if ring_m.size() >= 3:
		return _bounds_of(ring_m)
	var size: Vector2 = FALLBACK_FOOTPRINT_SIZE_M
	return Rect2(entrance.get_position_m() - size * 0.5, size)


## Authored interior scene when its id resolves, otherwise the procedural placeholder room.
func _instantiate_interior(entrance: Entrance) -> Interior:
	var interior_id: String = entrance.interior_id
	if not interior_id.is_empty():
		if not _is_safe_interior_id(interior_id):
			push_warning(
				"InteriorManager: interior id '%s' looks like a path; using the placeholder."
				% interior_id
			)
		else:
			var path: String = INTERIOR_SCENE_FORMAT % interior_id
			if ResourceLoader.exists(path):
				var scene: PackedScene = load(path) as PackedScene
				if scene != null:
					var instance: Node = scene.instantiate()
					if instance is Interior:
						instance.name = "Interior_%s" % interior_id
						return instance as Interior
					push_warning(
						"InteriorManager: %s does not extend Interior; using the placeholder." % path
					)
					if instance != null:
						instance.free()
	var placeholder := PlaceholderInterior.new()
	placeholder.name = "PlaceholderInterior"
	return placeholder


## Sets the placeholder room from the footprint and fills missing authored bounds.
func _configure_interior(interior: Interior, entrance: Entrance, footprint_m: Rect2) -> void:
	if interior is PlaceholderInterior:
		var placeholder := interior as PlaceholderInterior
		placeholder.room_size_m = _room_size_m(footprint_m)
		placeholder.room_label = (
			entrance.label if not entrance.label.is_empty() else entrance.get_building_osm_id()
		)
		return
	if interior.bounds_m.size.x <= 0.0 or interior.bounds_m.size.y <= 0.0:
		interior.bounds_m = Rect2(Vector2.ZERO, footprint_m.size)


## Placeholder rooms are clamped to a sane size.
func _room_size_m(footprint_m: Rect2) -> Vector2:
	return Vector2(
		clampf(footprint_m.size.x, ROOM_MIN_SIZE_M.x, ROOM_MAX_SIZE_M.x),
		clampf(footprint_m.size.y, ROOM_MIN_SIZE_M.y, ROOM_MAX_SIZE_M.y)
	)


func _place_actor_inside(actor: Entity, interior: Interior, footprint_m: Rect2) -> void:
	if interior.has_entry_point():
		actor.global_position = interior.get_entry_point_global()
		return
	var room_size_m: Vector2 = interior.get_bounds_m().size
	if room_size_m.x <= 0.0 or room_size_m.y <= 0.0:
		room_size_m = footprint_m.size
	actor.global_position = Units.to_px(INTERIOR_ORIGIN_M + room_size_m * 0.5)


## Camera limits for the room around the interior origin, in global meters.
func _camera_limits_m(interior: Interior) -> Rect2:
	var local_bounds: Rect2 = interior.get_bounds_m()
	if local_bounds.size.x <= 0.0 or local_bounds.size.y <= 0.0:
		local_bounds = Rect2(Vector2.ZERO, FALLBACK_FOOTPRINT_SIZE_M)
	return Rect2(INTERIOR_ORIGIN_M + local_bounds.position, local_bounds.size)


## First offset in front of the door that is neither a building nor water.
func _find_exit_point_m(entrance: Entrance) -> Vector2:
	var door_m: Vector2 = entrance.get_position_m()
	var normal: Vector2 = entrance.get_outward_normal()
	var query: TerrainQuery = TerrainQuery.active
	if query == null:
		return door_m + normal * EXIT_OFFSET_M
	for distance: float in EXIT_OFFSET_STEPS_M:
		var candidate: Vector2 = door_m + normal * distance
		var sample: TerrainSample = query.sample(candidate)
		if sample.category == &"buildings":
			continue
		if TerrainSample.is_water_landuse(sample.category, sample.kind):
			continue
		return candidate
	return door_m + normal * EXIT_OFFSET_M


## Authored interiors provide their own walls; the placeholder builds them from room_size_m.
func _free_interior() -> void:
	if _current_interior != null and is_instance_valid(_current_interior):
		_current_interior.queue_free()
	_current_interior = null


func _bounds_of(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


func _is_safe_interior_id(value: String) -> bool:
	if value.contains("/") or value.contains("\\") or value.contains(".."):
		return false
	return true


func _is_configured() -> bool:
	return (
		_interiors != null
		and _fader != null
		and _camera != null
		and _day_night != null
		and _map != null
	)
