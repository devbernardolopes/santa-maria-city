extends Node2D
## Headless interior test: footprint overlay, placeholder room, enter/exit, camera, clock.

const MAP_PATH: String = "res://data/map_test.json"
const MAP_WAIT_MS: int = 15000
const TRANSITION_WAIT_MS: int = 3000
const ENTRANCE_SCENE: PackedScene = preload("res://scenes/objects/entrance.tscn")
const ENTITY_SCENE: PackedScene = preload("res://scenes/entities/entity.tscn")

var _map: MapLoader = null
var _manager: InteriorManager = null
var _camera: FollowCamera = null
var _day_night: DayNight = null
var _player: Entity = null
var _entrance: Entrance = null
var _footprint_m: Rect2 = Rect2()
var _door_m: Vector2 = Vector2.ZERO
var _normal: Vector2 = Vector2.ZERO
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	await _run()
	if _failures.is_empty():
		print("INTERIOR SMOKE OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("INTERIOR SMOKE FAIL: %s" % failure)
	get_tree().quit(1)


func _run() -> void:
	_map = MapLoader.new()
	_map.name = "Map"
	_map.map_path = MAP_PATH
	add_child(_map)
	if not await _wait_for_map():
		return
	var objects := Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	add_child(objects)
	var interiors := Node2D.new()
	interiors.name = "Interiors"
	add_child(interiors)
	var fader := ScreenFader.new()
	fader.name = "ScreenFader"
	add_child(fader)
	_camera = FollowCamera.new()
	_camera.name = "FollowCamera"
	add_child(_camera)
	_day_night = DayNight.new()
	_day_night.name = "DayNight"
	add_child(_day_night)
	_manager = InteriorManager.new()
	_manager.name = "InteriorManager"
	add_child(_manager)
	_player = ENTITY_SCENE.instantiate() as Entity
	_player.name = "Player"
	add_child(_player)
	_camera.target = _player
	if not _build_entrance(objects):
		return
	await _test_enter()
	if not _manager.is_inside():
		return
	await _test_exit()


func _build_entrance(objects: Node2D) -> bool:
	var building_id: String = _pick_building()
	if building_id.is_empty():
		_fail("no usable building in %s" % MAP_PATH)
		return false
	var ring_m: PackedVector2Array = _map.get_building_ring_m(building_id)
	_footprint_m = _bounds_of(ring_m)
	var center_m: Vector2 = _footprint_m.get_center()
	var snap: Dictionary = BuildingGeometry.snap_to_edge(ring_m, center_m)
	var position_value: Variant = snap.get("position")
	var normal_value: Variant = snap.get("normal")
	if not (position_value is Vector2) or not (normal_value is Vector2):
		_fail("could not snap the test door to %s" % building_id)
		return false
	_door_m = position_value
	_normal = (normal_value as Vector2).normalized()
	if _normal.length_squared() <= 0.0:
		_fail("the test door has no outward normal")
		return false
	_entrance = ENTRANCE_SCENE.instantiate() as Entrance
	_entrance.name = "TestEntrance"
	_entrance.label = "Test Shop"
	_entrance.building_osm_id = building_id
	_entrance.position = Units.to_px(_door_m)
	_entrance.rotation = _normal.angle()
	objects.add_child(_entrance)
	_player.global_position = Units.to_px(_door_m + _normal)
	return true


func _test_enter() -> void:
	var interactable: Interactable = _entrance.get_node_or_null("Interactable") as Interactable
	if interactable == null:
		_fail("the entrance scene has no Interactable")
		return
	if not interactable.interact(_player):
		_fail("the test entrance rejected the interaction")
		return
	if not await _wait_for_inside():
		return
	_check("the manager reports being inside", _manager.is_inside())
	var interior: Interior = _manager.get_current_interior()
	if interior == null:
		_fail("no interior was created")
		return
	_check("the placeholder room fills the footprint", interior is PlaceholderInterior)
	if interior is PlaceholderInterior:
		var room := interior as PlaceholderInterior
		_check("the placeholder labels the room", room.room_label == "Test Shop")
		_check(
			"the room size is clamped",
			room.room_size_m.x >= 5.0
			and room.room_size_m.x <= 14.0
			and room.room_size_m.y >= 4.0
			and room.room_size_m.y <= 10.0
		)
		var expected_size := Vector2(
			clampf(_footprint_m.size.x, 5.0, 14.0), clampf(_footprint_m.size.y, 4.0, 10.0)
		)
		_check("the room keeps the footprint ratio when it fits", room.room_size_m.is_equal_approx(expected_size))
		var floor_polygon := interior.get_node_or_null("Floor") as Polygon2D
		_check("the floor draws behind the player", floor_polygon != null and floor_polygon.z_index < 0)
	_check("the room sits at the interior origin", _is_at_interior_origin(interior))
	_check("the player stands at the interior entry point", _at_entry_point(interior))
	_check("day/night is disabled inside", not _day_night.enabled)
	_check("the camera is limited to the room", _camera_limits_cover(interior))
	_check("a placeholder room has no extra shell", interior.get_node_or_null("InteriorShell") == null)


func _test_exit() -> void:
	var interior: Interior = _manager.get_current_interior()
	if interior == null:
		_fail("no interior to leave")
		return
	var exit := interior.get_node_or_null("Objects/Exit") as InteriorExit
	if exit == null:
		_fail("the placeholder room has no Exit")
		return
	exit.interact(_player)
	if not await _wait_for_outside():
		return
	_check("the manager reports being outside", not _manager.is_inside())
	_check("the current interior is cleared", _manager.get_current_interior() == null)
	_check("day/night is restored outside", _day_night.enabled)
	_check("camera limits are cleared", _camera.limit_left < 0 and _camera.limit_right > 1000000)
	var offset_m: Vector2 = Units.to_m(_player.global_position) - _door_m
	_check("the player returns outside along the normal", offset_m.dot(_normal) > 0.9)
	_check("the player returns close to the door", offset_m.length() < 2.5)


func _pick_building() -> String:
	for building_id: String in _map.get_building_ids():
		var ring_m: PackedVector2Array = _map.get_building_ring_m(building_id)
		if ring_m.size() < 3:
			continue
		var bounds: Rect2 = _bounds_of(ring_m)
		if bounds.size.x * bounds.size.y < 20.0:
			continue
		return building_id
	return ""


func _is_at_interior_origin(interior: Interior) -> bool:
	return Units.to_m(interior.global_position).is_equal_approx(InteriorManager.INTERIOR_ORIGIN_M)


func _at_entry_point(interior: Interior) -> bool:
	if not interior.has_entry_point():
		return false
	return _player.global_position.is_equal_approx(interior.get_entry_point_global())


func _camera_limits_cover(interior: Interior) -> bool:
	var width_px: float = float(_camera.limit_right - _camera.limit_left)
	var height_px: float = float(_camera.limit_bottom - _camera.limit_top)
	var bounds: Rect2 = interior.get_bounds_m()
	return (
		width_px >= Units.m_to_px(bounds.size.x) - 1.0
		and height_px >= Units.m_to_px(bounds.size.y) - 1.0
	)


func _wait_for_map() -> bool:
	var deadline: int = Time.get_ticks_msec() + MAP_WAIT_MS
	while not _map.is_loaded and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not _map.is_loaded:
		_fail("the test map did not load within %d ms" % MAP_WAIT_MS)
		return false
	return true


func _wait_for_inside() -> bool:
	var deadline: int = Time.get_ticks_msec() + TRANSITION_WAIT_MS
	while (
		(not _manager.is_inside() or _manager.is_transitioning())
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame
	if not _manager.is_inside() or _manager.is_transitioning():
		_fail("the enter transition did not finish within %d ms" % TRANSITION_WAIT_MS)
		return false
	return true


func _wait_for_outside() -> bool:
	var deadline: int = Time.get_ticks_msec() + TRANSITION_WAIT_MS
	while (
		(_manager.is_inside() or _manager.is_transitioning())
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame
	if _manager.is_inside() or _manager.is_transitioning():
		_fail("the exit transition did not finish within %d ms" % TRANSITION_WAIT_MS)
		return false
	return true


func _bounds_of(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


func _check(description: String, condition: bool) -> void:
	if not condition:
		_failures.append(description)


func _fail(message: String) -> void:
	_failures.append(message)
