extends Node2D
## Headless mini-map validation. Never loads the playable World scene.

const MAP_WAIT_MS: int = 15000

var _map: MapLoader = null
var _mini_map: MiniMap = null
var _focus: Node2D = null
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	await _run()
	if _failures.is_empty():
		print("MINI MAP SMOKE OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("MINI MAP SMOKE FAIL: %s" % failure)
	get_tree().quit(1)


func _run() -> void:
	var style: MapStyle = MapStyle.create_default()
	var grass_style: TerrainStyle = style.get_style(&"landuse", "grass")
	grass_style.color = Color("ff00ff")
	grass_style.texture = GradientTexture2D.new()
	_map = MapLoader.new()
	_map.map_path = "res://data/map_test.json"
	_map.style = style
	add_child(_map)
	if not await _wait_for_map():
		return
	_validate_index_and_flat_color()
	await _validate_control_behavior()


func _wait_for_map() -> bool:
	var deadline: int = Time.get_ticks_msec() + MAP_WAIT_MS
	while not _map.is_loaded and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if _map.is_loaded:
		return true
	_fail("map did not load within %d ms" % MAP_WAIT_MS)
	return false


func _validate_index_and_flat_color() -> void:
	var bounds_m := Rect2(
		Units.to_m(_map.map_bounds_px.position), Units.to_m(_map.map_bounds_px.size)
	)
	var entries: Array[Dictionary] = _map.get_mini_map_polygons(bounds_m)
	if entries.is_empty():
		_fail("mini-map index returned no polygons")
		return
	var previous_order: int = -1
	var found_textured_grass: bool = false
	for entry: Dictionary in entries:
		var order: int = int(entry.get("order", -1))
		if order <= previous_order:
			_fail("mini-map entries are not in draw order")
			break
		previous_order = order
		var polygon: Polygon2D = entry.get("polygon") as Polygon2D
		if polygon == null:
			_fail("mini-map entry has no polygon")
			continue
		if str(polygon.get_meta("kind", "")) == "grass" and polygon.texture != null:
			found_textured_grass = true
			var color_value: Variant = entry.get("color")
			if not (color_value is Color) or color_value != Color("ff00ff"):
				_fail("textured terrain did not retain its flat mini-map color")
	if not found_textured_grass:
		_fail("test setup did not create a textured grass polygon")
	var outside: Array[Dictionary] = _map.get_mini_map_polygons(Rect2(-1000.0, -1000.0, 10.0, 10.0))
	if not outside.is_empty():
		_fail("mini-map query returned polygons outside map bounds")


func _validate_control_behavior() -> void:
	_focus = Node2D.new()
	_focus.global_position = _map.map_bounds_px.get_center()
	add_child(_focus)
	_mini_map = MiniMap.new()
	_mini_map.size_px = Vector2(200.0, 100.0)
	_mini_map.visible_range_m = Vector2(120.0, 80.0)
	_mini_map.opacity = 0.4
	_mini_map.shape = MiniMap.Shape.SQUARE
	add_child(_mini_map)
	_mini_map.set_map(_map)
	_mini_map.set_focus(_focus)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _mini_map.get_effective_size_px().is_equal_approx(Vector2(100.0, 100.0)):
		_fail("square mini-map size was not normalized")
	if not is_equal_approx(_mini_map.opacity, 0.4):
		_fail("mini-map opacity was not retained")
	if _mini_map.get_drawn_polygon_count() <= 0:
		_fail("mini-map did not draw nearby polygons")
	var exterior_center: Vector2 = _mini_map._center_m
	_focus.global_position = Vector2(-160000.0, 0.0)
	await get_tree().process_frame
	if _mini_map._center_m != exterior_center:
		_fail("mini-map did not preserve its exterior center for an interior focus")
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_TAB
	toggle.pressed = true
	_mini_map._unhandled_input(toggle)
	if _mini_map.is_user_visible():
		_fail("Tab did not hide the mini-map")
	_mini_map._restore_button.emit_signal("pressed")
	if not _mini_map.is_user_visible():
		_fail("restore button did not show the mini-map")
	_mini_map.shape = MiniMap.Shape.RECTANGLE
	_mini_map.size_px = Vector2(200.0, 100.0)
	await get_tree().process_frame
	if not _mini_map.get_effective_size_px().is_equal_approx(Vector2(200.0, 100.0)):
		_fail("rectangle mini-map size changed unexpectedly")


func _fail(message: String) -> void:
	_failures.append(message)
