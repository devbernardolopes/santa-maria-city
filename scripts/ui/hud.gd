extends CanvasLayer
## Shows map feature counts and the required OpenStreetMap attribution.

const FALLBACK_ATTRIBUTION: String = "© OpenStreetMap contributors (ODbL)"
const FONT_REFERENCE_HEIGHT: float = 42.0
const MIN_FONT_SIZE: int = 14
const MAX_FONT_SIZE: int = 64

@onready var _label: Label = $Label

var _map: MapLoader = null


func _ready() -> void:
	_label.add_theme_color_override("font_color", Color("1e1e1e"))
	_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.85))
	_map = get_parent().get_node_or_null("Map") as MapLoader
	if _map != null:
		_map.map_loaded.connect(_on_map_loaded)
		if _map.is_loaded:
			_update_text()
	get_viewport().size_changed.connect(_update_font_size)
	_update_font_size()
	await get_tree().process_frame
	if _map == null or not _map.is_loaded:
		_label.text = "Map failed to load.\n%s" % FALLBACK_ATTRIBUTION


func _on_map_loaded(_counts: Dictionary) -> void:
	_update_text()


func _update_text() -> void:
	if _map == null:
		return
	var counts: Dictionary = {}
	var counts_value: Variant = _map.meta.get("counts")
	if counts_value is Dictionary:
		counts = counts_value
	var attribution: String = str(_map.meta.get("attribution", FALLBACK_ATTRIBUTION))
	_label.text = "Landuse %d · Waterways %d · Roads %d · Buildings %d\n%s" % [
		int(counts.get("landuse", 0)),
		int(counts.get("waterways", 0)),
		int(counts.get("roads", 0)),
		int(counts.get("buildings", 0)),
		attribution,
	]


func _update_font_size() -> void:
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var font_size: int = int(clampf(viewport_height / FONT_REFERENCE_HEIGHT, float(MIN_FONT_SIZE), float(MAX_FONT_SIZE)))
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.12)))
