extends Node2D
## Loads res://data/map.json (made by osm_to_godot.py) and draws it with Polygon2D.
## Attach this to a Node2D called "Map" in your main scene. A Camera2D is created
## in code: arrow keys pan, mouse wheel zooms.

const MAP_PATH := "res://data/map.json"
const PX_PER_METER := 8.0   # world scale; change freely

const LANDUSE_COLORS := {
	"residential": Color("e3dccd"),
	"grass": Color("b8d98a"),
	"wood": Color("7fb069"),
	"pitch": Color("9ccc7a"),
	"playground": Color("d9c8a0"),
}
const DEFAULT_LANDUSE_COLOR := Color("d8e0c8")
const WATER_COLOR := Color("7fb3d5")
const BUILDING_COLOR := Color("b5a69a")
const ROAD_COLORS := {
	"tertiary": Color("f2d98d"),
	"residential": Color("ffffff"),
	"service": Color("f0f0f0"),
	"footway": Color("e0b8b0"),
}
const DEFAULT_ROAD_COLOR := Color("eeeeee")

var camera: Camera2D


func _ready() -> void:
	var file := FileAccess.open(MAP_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % MAP_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	if data == null:
		push_error("Invalid JSON in %s" % MAP_PATH)
		return

	# Draw order = tree order: bottom layers first
	_build_layer(data["landuse"], "Landuse", func(f): return LANDUSE_COLORS.get(f["kind"], DEFAULT_LANDUSE_COLOR))
	_build_layer(data["waterways"], "Waterways", func(_f): return WATER_COLOR)
	_build_layer(data["roads"], "Roads", func(f): return ROAD_COLORS.get(f["kind"], DEFAULT_ROAD_COLOR))
	_build_layer(data["buildings"], "Buildings", func(_f): return BUILDING_COLOR)

	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * 0.1
	add_child(camera)
	print("Map loaded: ", data["meta"]["counts"])


func _build_layer(features: Array, layer_name: String, color_fn: Callable) -> void:
	var layer := Node2D.new()
	layer.name = layer_name
	add_child(layer)
	for feature in features:
		var color: Color = color_fn.call(feature)
		for poly in feature["polys"]:
			# poly[0] is the outer ring; poly[1..] are holes (ignored for now)
			var points := PackedVector2Array()
			for p in poly[0]:
				points.append(Vector2(p[0], p[1]) * PX_PER_METER)
			if points.size() < 3:
				continue
			var node := Polygon2D.new()
			node.polygon = points
			node.color = color
			node.set_meta("osm_id", feature["id"])  # link back to OSM / your own data
			node.set_meta("kind", feature["kind"])
			layer.add_child(node)


func _process(delta: float) -> void:
	if camera == null:
		return
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	camera.position += dir * 1500.0 * delta / camera.zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if camera == null or not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera.zoom = (camera.zoom * 1.15).clamp(Vector2.ONE * 0.02, Vector2.ONE * 4.0)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera.zoom = (camera.zoom / 1.15).clamp(Vector2.ONE * 0.02, Vector2.ONE * 4.0)
