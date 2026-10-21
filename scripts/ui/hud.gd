class_name Hud
extends CanvasLayer
## Shows map counts, attribution, the clock and weather line, the player state, and pick reports.

const FALLBACK_ATTRIBUTION: String = "© OpenStreetMap contributors (ODbL)"
const FONT_REFERENCE_HEIGHT: float = 42.0
const MIN_FONT_SIZE: int = 14
const MAX_FONT_SIZE: int = 64
const INFO_FONT_SCALE: float = 0.8
const INFO_TAG_LIMIT: int = 8
const INFO_VALUE_MAX_LENGTH: int = 48
const PLAYER_UPDATE_INTERVAL_S: float = 0.25
const DEBUG_BUTTON_MIN_HEIGHT: float = 44.0
const DEBUG_BUTTON_HEIGHT_SCALE: float = 2.0
const TIME_SCALE_OPTIONS: Array[float] = [1.0, 60.0, 600.0, 3600.0]
const PROMPT_BOTTOM_MARGIN: float = 96.0
const CONDITION_NAMES: Dictionary = {
	WeatherSample.Condition.CLEAR: "Clear",
	WeatherSample.Condition.CLOUDY: "Cloudy",
	WeatherSample.Condition.RAIN: "Rain",
}

@onready var _label: Label = $TextStack/Label
@onready var _clock_label: Label = $TextStack/ClockLabel
@onready var _player_label: Label = $TextStack/PlayerLabel
@onready var _info_label: Label = $TextStack/InfoLabel
@onready var _time_debug: HBoxContainer = $TextStack/TimeDebug
@onready var _pause_button: Button = $TextStack/TimeDebug/PauseButton
@onready var _scale_button: Button = $TextStack/TimeDebug/ScaleButton
@onready var _hour_button: Button = $TextStack/TimeDebug/HourButton
@onready var _bottom_stack: VBoxContainer = $BottomStack
@onready var _message_label: Label = $BottomStack/MessageLabel
@onready var _prompt_label: Label = $BottomStack/PromptLabel
@onready var _message_timer: Timer = $BottomStack/MessageTimer

var _map: MapLoader = null
var _player: Entity = null
var _player_update_timer: float = 0.0


func _ready() -> void:
	for label: Label in [_label, _clock_label, _player_label, _info_label, _message_label, _prompt_label]:
		label.add_theme_color_override("font_color", Color("1e1e1e"))
		label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.85))
	_map = get_parent().get_node_or_null("Map") as MapLoader
	if _map != null and _map.is_loaded:
		_update_text(_counts_from_map())
	_time_debug.visible = OS.is_debug_build()
	_pause_button.pressed.connect(_on_pause_pressed)
	_scale_button.pressed.connect(_on_scale_pressed)
	_hour_button.pressed.connect(_on_hour_pressed)
	GameClock.minute_changed.connect(_update_clock_text)
	GameClock.time_scale_changed.connect(_on_time_scale_changed)
	GameClock.paused_changed.connect(_on_paused_changed)
	GameWeather.weather_changed.connect(_on_weather_changed)
	_message_label.visible = false
	_prompt_label.visible = false
	if _message_timer != null:
		_message_timer.timeout.connect(_on_message_timeout)
	_update_clock_text()
	_update_debug_buttons()
	get_viewport().size_changed.connect(_update_font_size)
	_update_font_size()
	await get_tree().process_frame
	if _map == null or not _map.is_loaded:
		_label.text = "Map failed to load.\n%s" % FALLBACK_ATTRIBUTION


func _process(delta: float) -> void:
	if _player == null:
		return
	if not is_instance_valid(_player):
		_player = null
		_player_label.text = ""
		return
	_player_update_timer -= delta
	if _player_update_timer <= 0.0:
		_player_update_timer = PLAYER_UPDATE_INTERVAL_S
		_update_player_text()


func set_player(player: Entity) -> void:
	_player = player
	_player_update_timer = 0.0
	_update_player_text()


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
	var point_value: Variant = info.get("point_m")
	if point_value is Vector2:
		var point_m: Vector2 = point_value
		lines.append("at x %.1f m · y %.1f m" % [point_m.x, point_m.y])
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


## Show or hide the bottom-center interaction prompt.
func set_interaction_prompt(text: String) -> void:
	if _prompt_label == null:
		return
	if text.is_empty():
		_prompt_label.visible = false
		_prompt_label.text = ""
		return
	_prompt_label.text = text
	_prompt_label.visible = true


## Show a temporary message above the prompt; replaces any existing message.
func show_message(text: String, seconds: float = 2.5) -> void:
	if _message_label == null:
		return
	if text.is_empty():
		_message_label.visible = false
		_message_label.text = ""
		if _message_timer != null:
			_message_timer.stop()
		return
	_message_label.text = text
	_message_label.visible = true
	if _message_timer != null:
		_message_timer.stop()
		_message_timer.wait_time = maxf(0.1, seconds)
		_message_timer.start()


func _update_player_text() -> void:
	if _player == null or not is_instance_valid(_player) or _player.data == null:
		_player_label.text = ""
		return
	var position_m := Vector2(
		Units.px_to_m(_player.global_position.x),
		Units.px_to_m(_player.global_position.y)
	)
	var data: EntityData = _player.data
	var parts: PackedStringArray = [
		"%s, %d" % [
			data.full_name,
			data.get_age_years(GameClock.get_year(), GameClock.get_month(), GameClock.get_day()),
		],
		"x %.1f m · y %.1f m" % [position_m.x, position_m.y],
	]
	var terrain_text: String = _terrain_text(_player.current_terrain)
	if not terrain_text.is_empty():
		parts.append(terrain_text)
	_player_label.text = " · ".join(parts)


## "road · residential · asphalt", "landuse · grass", or "ground"; empty parts omitted.
func _terrain_text(sample: TerrainSample) -> String:
	if sample == null:
		return ""
	var parts: PackedStringArray = [_category_label(sample.category)]
	if not sample.kind.is_empty() and sample.kind != sample.category:
		parts.append(String(sample.kind))
	if not sample.surface.is_empty():
		parts.append(String(sample.surface))
	return " · ".join(parts)


func _category_label(category: StringName) -> String:
	match category:
		&"roads":
			return "road"
		&"buildings":
			return "building"
		&"waterways":
			return "waterway"
		_:
			return String(category)


func _update_clock_text() -> void:
	var parts: PackedStringArray = [GameClock.format_date(), GameClock.format_time()]
	var sample: WeatherSample = GameWeather.current
	if sample != null:
		parts.append("%.1f °C" % sample.temperature_c)
		parts.append(_condition_name(sample.condition))
	if GameClock.paused:
		parts.append("paused")
	else:
		parts.append("×%.0f" % GameClock.time_scale)
	_clock_label.text = " · ".join(parts)


func _condition_name(condition: WeatherSample.Condition) -> String:
	return str(CONDITION_NAMES.get(condition, "Clear"))


func _on_time_scale_changed(_value: float) -> void:
	_update_clock_text()
	_update_debug_buttons()


func _on_paused_changed(_value: bool) -> void:
	_update_clock_text()
	_update_debug_buttons()


func _on_weather_changed(_sample: WeatherSample) -> void:
	_update_clock_text()


func _update_debug_buttons() -> void:
	_pause_button.text = "Resume" if GameClock.paused else "Pause"
	_scale_button.text = "×%.0f" % GameClock.time_scale


func _on_pause_pressed() -> void:
	GameClock.set_paused(not GameClock.paused)


func _on_scale_pressed() -> void:
	var next_scale: float = TIME_SCALE_OPTIONS[0]
	for option: float in TIME_SCALE_OPTIONS:
		if option > GameClock.time_scale + 0.001:
			next_scale = option
			break
	GameClock.set_time_scale(next_scale)


func _on_hour_pressed() -> void:
	GameClock.advance_hours(1.0)


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


func _on_message_timeout() -> void:
	if _message_label != null:
		_message_label.visible = false
		_message_label.text = ""


func _update_font_size() -> void:
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var font_size: int = int(clampf(viewport_height / FONT_REFERENCE_HEIGHT, float(MIN_FONT_SIZE), float(MAX_FONT_SIZE)))
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.12)))
	var info_font_size: int = maxi(MIN_FONT_SIZE, int(round(font_size * INFO_FONT_SCALE)))
	_player_label.add_theme_font_size_override("font_size", info_font_size)
	_player_label.add_theme_constant_override("outline_size", maxi(2, int(info_font_size * 0.12)))
	_info_label.add_theme_font_size_override("font_size", info_font_size)
	_info_label.add_theme_constant_override("outline_size", maxi(2, int(info_font_size * 0.12)))
	_clock_label.add_theme_font_size_override("font_size", info_font_size)
	_clock_label.add_theme_constant_override("outline_size", maxi(2, int(info_font_size * 0.12)))
	if _message_label != null:
		_message_label.add_theme_font_size_override("font_size", font_size)
		_message_label.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.12)))
	if _prompt_label != null:
		_prompt_label.add_theme_font_size_override("font_size", font_size)
		_prompt_label.add_theme_constant_override("outline_size", maxi(2, int(font_size * 0.12)))
	if _bottom_stack != null:
		_bottom_stack.offset_bottom = -PROMPT_BOTTOM_MARGIN
	var button_height: float = maxf(DEBUG_BUTTON_MIN_HEIGHT, font_size * DEBUG_BUTTON_HEIGHT_SCALE)
	for button: Button in [_pause_button, _scale_button, _hour_button]:
		button.add_theme_font_size_override("font_size", info_font_size)
		button.custom_minimum_size = Vector2(0.0, button_height)
