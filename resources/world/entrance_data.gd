class_name EntranceData
extends Resource
## One building entrance, parsed from res://data/overlays/entrances.json.

## Prompt prefix; the label is appended when present.
const ENTER_TEXT: String = "Enter"

@export var id: String = ""
@export var building_osm_id: String = ""
## Approximate position from the file, snapped to the footprint edge by EntranceSpawner.
@export var position_m: Vector2 = Vector2.ZERO
## Outward unit normal of the snapped edge; Vector2.ZERO before snapping.
@export var normal: Vector2 = Vector2.ZERO
## Scene id under res://scenes/interiors/; empty uses the placeholder room.
@export var interior_id: String = ""
@export var label: String = ""
@export var locked: bool = false
## [{"days": [0..6], "from": hour, "to": hour}]; empty means always open.
@export var schedule: Array[Dictionary] = []


## Validates a JSON entry; returns null when anything is invalid.
static func from_dict(source: Dictionary) -> EntranceData:
	var id_value: Variant = source.get("id")
	if not (id_value is String) or String(id_value).is_empty():
		return null
	var building_value: Variant = source.get("building")
	if not (building_value is String) or String(building_value).is_empty():
		return null
	var position_value: Variant = source.get("position")
	if not (position_value is Array):
		return null
	var position: Array = position_value
	if position.size() != 2 or not _is_number(position[0]) or not _is_number(position[1]):
		return null
	var interior_value: Variant = source.get("interior", "")
	if not (interior_value is String):
		return null
	var interior_text: String = String(interior_value)
	if not interior_text.is_empty() and not _is_safe_interior_id(interior_text):
		return null
	var label_value: Variant = source.get("label", "")
	if not (label_value is String):
		return null
	var locked_value: Variant = source.get("locked", false)
	if not (locked_value is bool):
		return null
	var schedule_value: Variant = source.get("schedule", [])
	if not (schedule_value is Array):
		return null
	var parsed_schedule: Array[Dictionary] = []
	for entry_value: Variant in schedule_value:
		if not (entry_value is Dictionary):
			return null
		var entry: Dictionary = _parse_schedule_entry(entry_value)
		if entry.is_empty():
			return null
		parsed_schedule.append(entry)
	var data := EntranceData.new()
	data.id = String(id_value)
	data.building_osm_id = String(building_value)
	data.position_m = Vector2(float(position[0]), float(position[1]))
	data.interior_id = interior_text
	data.label = String(label_value)
	data.locked = locked_value
	data.schedule = parsed_schedule
	return data


## No schedule means always open. The listed day is the day the interval starts;
## to < from wraps past midnight into the following day.
func is_open(weekday: int, hour: float) -> bool:
	if schedule.is_empty():
		return true
	var previous_weekday: int = wrapi(weekday - 1, 0, 7)
	for entry: Dictionary in schedule:
		var days: Array = _entry_days(entry)
		var from_hour: float = _entry_hour(entry, "from")
		var to_hour: float = _entry_hour(entry, "to")
		if from_hour < to_hour:
			if days.has(weekday) and hour >= from_hour and hour < to_hour:
				return true
		elif from_hour > to_hour:
			if days.has(weekday) and hour >= from_hour:
				return true
			if days.has(previous_weekday) and hour < to_hour:
				return true
	return false


## "HH:MM" of the next opening at or after now, searching seven days ahead.
func next_opening_text(weekday: int, hour: float) -> String:
	var best_offset: int = -1
	var best_from: float = 24.0
	for entry: Dictionary in schedule:
		var days: Array = _entry_days(entry)
		var from_hour: float = _entry_hour(entry, "from")
		for offset: int in range(7):
			if not days.has(wrapi(weekday + offset, 0, 7)):
				continue
			if offset == 0 and from_hour <= hour:
				continue
			var candidate: float = float(offset) * 24.0 + from_hour
			if best_offset < 0 or candidate < float(best_offset) * 24.0 + best_from:
				best_offset = offset
				best_from = from_hour
			break
	if best_offset < 0:
		return "00:00"
	var total_minutes: int = int(round(best_from * 60.0))
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]


## Prompt for the Interactable: "Enter" or "Enter Bakery".
func get_prompt_text() -> String:
	return ENTER_TEXT if label.is_empty() else "%s %s" % [ENTER_TEXT, label]


static func _parse_schedule_entry(source: Dictionary) -> Dictionary:
	var days_value: Variant = source.get("days")
	if not (days_value is Array):
		return {}
	var days_array: Array = days_value
	if days_array.is_empty():
		return {}
	var days: Array[int] = []
	for day_value: Variant in days_array:
		if not _is_number(day_value):
			return {}
		var day: int = int(day_value)
		if day < 0 or day > 6:
			return {}
		days.append(day)
	var from_value: Variant = source.get("from")
	var to_value: Variant = source.get("to")
	if not _is_number(from_value) or not _is_number(to_value):
		return {}
	var from_hour: float = float(from_value)
	var to_hour: float = float(to_value)
	if from_hour < 0.0 or from_hour > 24.0 or to_hour < 0.0 or to_hour > 24.0:
		return {}
	return {"days": days, "from": from_hour, "to": to_hour}


static func _entry_days(entry: Dictionary) -> Array:
	var days_value: Variant = entry.get("days")
	if days_value is Array:
		return days_value
	return []


static func _entry_hour(entry: Dictionary, key: String) -> float:
	var value: Variant = entry.get(key)
	if _is_number(value):
		return float(value)
	return 0.0


## interior_id is used as a scene path segment; reject anything path-like.
static func _is_safe_interior_id(value: String) -> bool:
	if value.contains("/") or value.contains("\\") or value.contains(".."):
		return false
	return true


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
