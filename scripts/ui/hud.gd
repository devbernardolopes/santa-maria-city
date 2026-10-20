class_name Hud
extends CanvasLayer
## Shows map feature counts, attribution, and the debug polygon picker report.

const FALLBACK_ATTRIBUTION: String = "© OpenStreetMap contributors (ODbL)"
const FONT_REFERENCE_HEIGHT: float = 42.0
const MIN_FONT_SIZE: int = 14
const MAX_FONT_SIZE: int = 64
const INFO_FONT_SCALE: float = 0.8
const INFO_TAG_LIMIT: int = 8
const INFO_VALUE_MAX_LENGTH: int = 48

@onready var _label: Label = $Label
@onready var _info_label: Label = $InfoLabel

var _map: MapLoader = null


func _ready() -> void:
	for label: Label in [_label, _info_label]:
		label.add_theme_color_override("font_color", Color("1e1e1e"))
		label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.85))
	_map = get_parent().get_node_or_null("Map") as MapLoader
	if _map != null and _map.is_loaded:
		_update_text(_counts_from_map())
	get_viewport().size_changed.connect(_update_font_size)
	_update_font_size()
	await get_tree().process_frame
	if _map == null or not _map.is_loaded:
		_label.text = "Map failed to load.\n%s" % FALLBACK_ATTRIBUTION


func on_map_loaded(counts: Dictionary) -> void:
	_update_text(counts)


func show_pick(info: Dictionary) -> void:
	if info.is_empty():
		_info_label.text = ""
		return
	var osm_id: String = str(info.get("id", ""))
	var category: String = str(info.get("category", ""))
	var kind: String = str(info.get("kind", ""))
	var surface: String = str(info.get("surface", ""))
	var style_id: String = str(info.get("style_id", ""))
	var surface_text: String = surface if not surface.is_empty() else "(none)"
	var lines: PackedStringArray = [
		"%s · %s · %s" % [osm_id, category, kind],
		"surface: %s · style: %s" % [surface_text, style_id],
	]
	var tags: Dictionary = {}
	var tags_value: Variant = info.get("tags")
	if tags_value is Dictionary:
		tags = tags_value
	var tag_keys: Array[String] = []
	for key_value: Variant in tags:
		tag_keys.append(str(key_value))
	tag_keys.sort()
	var limit: int = mini(INFO_TAG_LIMIT, tag_keys.size())
	for index: int in range(limit):
		var key: String = tag_keys[index]
		var value: String = _truncate(str(tags.get(key, "")))
		lines.append("%s=%s" % [key, value])
	_info_label.text = "\n".join(lines)


func _counts_from_map() -> Dictionary:
	if _map == null:
		return {}
	var counts_value: Variant = _map.meta.get("counts")
	if counts_value is Dictionary:
		return counts_value
	return {}


func _update_text(counts: Dictionary) -> void:
	if _map == null:
		return
	var attribution: String = str(_map.meta.get("attribution", FALLBACK_ATTRIBUTION))
	_label.text = "Landuse %d · Waterways %d · Roads %d · Buildings %d\n%s" % [
		int(counts.get("landuse", 0)),
		int(counts.get("waterways", 0)),
		int(counts.get("roads", 0)),
		int(counts.get("buildings", 0)),
		attribution,
	]


func _truncate(value: String) -> String:
	if value.length() <= INFO_VALUE_MAX_LENGTH:
		return value
	return value.left(INFO_VALUE_MAX_LENGTH - 1) + "…"


func _update_font_size() -> void:
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var font_size: int = int(clampf(viewport_height / FONT_REFERENCE_HEIGHT, float(MIN_FONT_SIZE), float(MAX_FONT_SIZE)))
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.12)))
	var info_font_size: int = maxi(MIN_FONT_SIZE, int(round(font_size * INFO_FONT_SCALE)))
	_info_label.add_theme_font_size_override("font_size", info_font_size)
	_info_label.add_theme_constant_override("outline_size", maxi(2, int(info_font_size * 0.12)))
