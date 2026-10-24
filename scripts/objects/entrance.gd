@tool
class_name Entrance
extends Node2D
## A door, gate, or archway on a building footprint, authored directly in the world scene.
##
## The node transform is the entrance: `position` is the anchor on the wall and the node's
## +X axis is the outward normal, so `rotation` points away from the building. Nodes live in
## `World/Objects/Entrances`. With no SpriteFrames a flat placeholder is drawn, so missing art
## never breaks the scene.
##
## `locked`, the lock entries, the opening schedule, and the physical properties are authored
## now; the item, strike, and lockpicking systems that consume them ship later.

const ENTER_TEXT: String = "Enter"
const LOCKED_TEXT: String = "Locked"
const CLOSED_TEXT_FORMAT: String = "Closed · opens %s"

const OPEN_COLOR: Color = Color(0.25, 0.7, 0.35, 0.9)
const CLOSED_COLOR: Color = Color(0.6, 0.6, 0.6, 0.9)
const LOCKED_COLOR: Color = Color(0.85, 0.3, 0.25, 0.9)
const EDITOR_NORMAL_COLOR: Color = Color(1.0, 0.95, 0.6, 0.9)
const EDITOR_LABEL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
const EDITOR_LABEL_SIZE: int = 10
const EDITOR_LABEL_WIDTH_PX: float = 120.0

## How far from the node the "Snap to nearest wall" search looks, in meters.
const SNAP_SEARCH_RADIUS_M: float = 8.0
## How far inside the wall the terrain probe looks for the building when none is authored.
const BUILDING_PROBE_M: float = 0.35
const DEFAULT_FRAME_WIDTH_PX: float = 1.0

enum Kind {
	DOOR,
	DOUBLE_DOOR,
	SLIDING_DOOR,
	GARAGE_DOOR,
	GATE,
	ARCHWAY,
}

@export_group("Identity")
## Stable save key; falls back to the node name when empty.
@export var id: String = ""
## Shown in the prompt: "Enter Bakery". Empty keeps "Enter".
@export var label: String = ""
## Building OSM id, filled by "Snap to nearest wall"; resolved at runtime when empty.
@export var building_osm_id: String = ""
## Scene id under res://scenes/interiors/; empty builds the placeholder room.
@export var interior_id: String = ""

@export_group("Door")
@export var kind: Kind = Kind.DOOR:
	set(value):
		kind = value
		_apply_visual()
## Extent along the wall, in meters.
@export_range(0.4, 8.0, 0.05, "suffix:m") var width_m: float = 1.2:
	set(value):
		width_m = value
		_apply_visual()
## Extent along the outward normal, in meters.
@export_range(0.05, 1.0, 0.01, "suffix:m") var thickness_m: float = 0.25:
	set(value):
		thickness_m = value
		queue_redraw()

@export_group("Animation")
## Door art. Clips are authored here; only open/closed playback is driven today.
@export var sprite_frames: SpriteFrames = null:
	set(value):
		sprite_frames = value
		_apply_visual()
## Width the whole frame is drawn at, in meters; drives the world scale of the art.
@export_range(0.2, 8.0, 0.01, "suffix:m") var sprite_width_m: float = 1.2:
	set(value):
		sprite_width_m = value
		_apply_visual()
## North-facing art needs +90° so its face points along the node's +X normal.
@export_range(-180.0, 180.0, 1.0, "suffix:°") var sprite_facing_offset_deg: float = 90.0:
	set(value):
		sprite_facing_offset_deg = value
		_apply_visual()
@export var open_clip: StringName = &"open":
	set(value):
		open_clip = value
		_apply_visual()
@export var closed_clip: StringName = &"closed":
	set(value):
		closed_clip = value
		_apply_visual()
## Optional one-shot clips, played when the door gets an open/close state machine.
@export var opening_clip: StringName = &"opening"
@export var closing_clip: StringName = &"closing"

@export_group("Access")
## Locked entrances cannot be entered until the lock system ships; authoring only for now.
@export var locked: bool = false:
	set(value):
		locked = value
		queue_redraw()
## One entry per physical lock; a key opens only the locks whose key id it matches.
@export var locks: Array[EntranceLock] = []
## Opening hours. Empty means always open.
@export var schedule: Array[EntranceScheduleEntry] = []

@export_group("Physical properties")
## Shared world-object description; breaking and fire fields are authored now, consumed later.
@export var properties: ObjectProperties = ObjectProperties.new()

@export_tool_button("Snap to nearest wall") var snap_button: Callable = snap_to_nearest_wall

@onready var _interactable: Interactable = get_node_or_null("Interactable") as Interactable

var _is_open: bool = true
var _available: bool = true
var _display_open: bool = true
var _sprite: AnimatedSprite2D = null
var _applied_clip: StringName = &""


func _ready() -> void:
	_apply_visual()
	if Engine.is_editor_hint():
		queue_redraw()
		return
	if _interactable != null:
		_interactable.interacted.connect(_on_interacted)
	GameClock.minute_changed.connect(_on_minute_changed)
	refresh_availability(GameClock.get_weekday(), GameClock.get_hour_float())


func get_save_key() -> String:
	return id if not id.is_empty() else name


## Outward normal in world space (the node's +X axis).
func get_outward_normal() -> Vector2:
	var normal: Vector2 = global_transform.x
	if normal.length_squared() <= 0.0:
		return Vector2.DOWN
	return normal.normalized()


## Door anchor in global meters.
func get_position_m() -> Vector2:
	return Units.to_m(global_position)


## Authored building id, or the building under the inward probe when none is authored.
func get_building_osm_id() -> String:
	if not building_osm_id.is_empty():
		return building_osm_id
	var query: TerrainQuery = TerrainQuery.active
	if query == null:
		return ""
	var probe_m: Vector2 = get_position_m() - get_outward_normal() * BUILDING_PROBE_M
	var sample: TerrainSample = query.sample(probe_m)
	if sample.category == &"buildings":
		return sample.osm_id
	return ""


func get_prompt_text() -> String:
	return ENTER_TEXT if label.is_empty() else "%s %s" % [ENTER_TEXT, label]


## Availability and prompt at a moment in time; pure so tests need no clock.
func evaluate(weekday: int, hour: float) -> Dictionary:
	var open_now: bool = EntranceSchedule.is_open(schedule, weekday, hour)
	if locked:
		return {"available": false, "open": open_now, "prompt": LOCKED_TEXT}
	if not open_now:
		return {
			"available": false,
			"open": false,
			"prompt": CLOSED_TEXT_FORMAT % EntranceSchedule.next_opening_text(schedule, weekday, hour),
		}
	return {"available": true, "open": true, "prompt": get_prompt_text()}


## Recomputes the interaction prompt for a specific moment, instead of the live clock.
func refresh_availability(weekday: int, hour: float) -> void:
	var result: Dictionary = evaluate(weekday, hour)
	_is_open = bool(result["open"])
	_available = bool(result["available"])
	_display_open = _is_open and not locked
	if _interactable != null:
		if _available:
			_interactable.available = true
			_interactable.prompt_text = String(result["prompt"])
		else:
			_interactable.set_available(false, String(result["prompt"]))
	_apply_visual()
	queue_redraw()


func is_available() -> bool:
	return _available


func is_open_now() -> bool:
	return _is_open


func is_locked() -> bool:
	return locked


func get_total_locks() -> int:
	return locks.size()


## Locks a key with this item id can open; only matching locks count.
func get_matching_locks(key_item_id: StringName) -> Array[EntranceLock]:
	var matched: Array[EntranceLock] = []
	if key_item_id == &"":
		return matched
	for lock: EntranceLock in locks:
		if lock != null and lock.required_key_item_id == key_item_id:
			matched.append(lock)
	return matched


## Clip currently playing, or an empty name while the placeholder is drawn.
func get_current_clip() -> StringName:
	return _applied_clip


## Whether the placeholder is what the player sees.
func is_using_placeholder() -> bool:
	return _sprite == null or not _sprite.visible


## Snaps the node to the nearest building wall and records the building id.
func snap_to_nearest_wall() -> void:
	var map: MapLoader = _find_map()
	if map == null or not map.is_loaded:
		push_warning("Entrance '%s': the map is not loaded; rebuild it and try again." % name)
		return
	var layer: Node2D = map.get_node_or_null("Buildings") as Node2D
	if layer == null:
		push_warning("Entrance '%s': the map has no Buildings layer." % name)
		return
	var origin_px: Vector2 = global_position
	var search_px: float = Units.m_to_px(SNAP_SEARCH_RADIUS_M)
	var best_position_m: Vector2 = Units.to_m(origin_px)
	var best_normal: Vector2 = Vector2.ZERO
	var best_id: String = ""
	var best_distance: float = INF
	for child: Node in layer.get_children():
		var polygon := child as Polygon2D
		if polygon == null or polygon.polygon.size() < 3:
			continue
		if not _bounds_of(polygon.polygon).grow(search_px).has_point(origin_px):
			continue
		var ring_m: PackedVector2Array = _ring_to_m(polygon.polygon)
		var snap: Dictionary = BuildingGeometry.snap_to_edge(ring_m, Units.to_m(origin_px))
		var position_value: Variant = snap.get("position")
		var normal_value: Variant = snap.get("normal")
		if not (position_value is Vector2) or not (normal_value is Vector2):
			continue
		var normal: Vector2 = normal_value
		if normal.length_squared() <= 0.0:
			continue
		var snapped_position_m: Vector2 = position_value
		var distance: float = origin_px.distance_squared_to(Units.to_px(snapped_position_m))
		if distance >= best_distance:
			continue
		best_distance = distance
		best_position_m = snapped_position_m
		best_normal = normal
		var id_value: Variant = polygon.get_meta("osm_id", "")
		best_id = str(id_value)
	position = Units.to_px(best_position_m)
	if best_normal.length_squared() > 0.0:
		rotation = best_normal.angle()
	if not best_id.is_empty():
		building_osm_id = best_id
	_apply_visual()
	queue_redraw()


func _on_minute_changed() -> void:
	refresh_availability(GameClock.get_weekday(), GameClock.get_hour_float())


func _on_interacted(actor: Entity) -> void:
	if not _available or actor == null:
		return
	var manager: InteriorManager = InteriorManager.active
	if manager == null:
		push_warning("Entrance '%s': no InteriorManager in the scene; cannot enter." % name)
		return
	_play_one_shot(opening_clip)
	manager.enter(self, actor)


func _apply_visual() -> void:
	if not is_node_ready():
		return
	_display_open = not locked and (_is_open if not Engine.is_editor_hint() else true)
	if not _has_any_clip():
		_clear_sprite()
		queue_redraw()
		return
	_ensure_sprite()
	_sprite.sprite_frames = sprite_frames
	_sprite.rotation = deg_to_rad(sprite_facing_offset_deg)
	_sprite.scale = Vector2.ONE * _get_sprite_scale()
	_sprite.visible = true
	_play_clip(_get_state_clip())
	queue_redraw()


func _get_state_clip() -> StringName:
	var preferred: Array[StringName] = [closed_clip, open_clip]
	if _display_open:
		preferred = [open_clip, closed_clip]
	for clip: StringName in preferred:
		if _has_clip(clip):
			return clip
	var names: PackedStringArray = sprite_frames.get_animation_names()
	return StringName(names[0]) if not names.is_empty() else &""


func _get_sprite_scale() -> float:
	if sprite_frames == null or sprite_width_m <= 0.0:
		return 1.0
	var clip: StringName = _get_state_clip()
	var width_px: float = DEFAULT_FRAME_WIDTH_PX
	if _has_clip(clip):
		var texture: Texture2D = sprite_frames.get_frame_texture(clip, 0)
		if texture != null:
			width_px = maxf(texture.get_size().x, DEFAULT_FRAME_WIDTH_PX)
	return Units.m_to_px(sprite_width_m) / width_px


func _has_any_clip() -> bool:
	return (
		sprite_frames != null
		and not sprite_frames.get_animation_names().is_empty()
		and (open_clip != &"" or closed_clip != &"")
	)


func _has_clip(clip: StringName) -> bool:
	if sprite_frames == null or clip == &"" or not sprite_frames.has_animation(clip):
		return false
	return sprite_frames.get_frame_count(clip) > 0


func _play_clip(clip: StringName) -> void:
	if _sprite == null or not _has_clip(clip):
		_clear_sprite()
		return
	if clip == _applied_clip:
		return
	_applied_clip = clip
	_sprite.animation = clip
	_sprite.play()


func _play_one_shot(clip: StringName) -> void:
	if _sprite == null or not _has_clip(clip):
		return
	_applied_clip = clip
	_sprite.animation = clip
	_sprite.play()


func _ensure_sprite() -> void:
	if _sprite != null:
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite, false, Node.INTERNAL_MODE_FRONT)


func _clear_sprite() -> void:
	_applied_clip = &""
	if _sprite == null:
		return
	_sprite.stop()
	_sprite.visible = false


func _draw() -> void:
	if _sprite != null and _sprite.visible:
		return
	var color: Color = _get_placeholder_color()
	match kind:
		Kind.DOUBLE_DOOR:
			_draw_double_door(color)
		Kind.SLIDING_DOOR:
			_draw_sliding_door(color)
		Kind.GARAGE_DOOR:
			_draw_garage_door(color)
		Kind.GATE:
			_draw_gate(color)
		Kind.ARCHWAY:
			_draw_archway(color)
		_:
			_draw_panel(
				Rect2(-thickness_m * 0.5, -width_m * 0.5, thickness_m, width_m), color, true
			)
	if Engine.is_editor_hint():
		_draw_editor_marker()
		_draw_editor_label()


func _get_placeholder_color() -> Color:
	if locked:
		return LOCKED_COLOR
	if not _display_open:
		return CLOSED_COLOR
	return OPEN_COLOR


func _draw_double_door(color: Color) -> void:
	var half_width: float = width_m * 0.5
	var gap: float = width_m * 0.05
	var leaf: float = half_width - gap
	_draw_panel(Rect2(-thickness_m * 0.5, -half_width, thickness_m, leaf), color, true)
	_draw_panel(Rect2(-thickness_m * 0.5, gap, thickness_m, leaf), color, true)


func _draw_sliding_door(color: Color) -> void:
	_draw_panel(Rect2(-thickness_m * 0.5, -width_m * 0.5, thickness_m, width_m), color.darkened(0.35), false)
	_draw_panel(
		Rect2(-thickness_m * 0.5, -width_m * 0.5, thickness_m, width_m * 0.6), color, true
	)


func _draw_garage_door(color: Color) -> void:
	_draw_panel(Rect2(-thickness_m * 0.5, -width_m * 0.5, thickness_m, width_m), color, true)
	var rows: int = maxi(2, int(ceilf(width_m / 0.5)))
	var line_color: Color = color.darkened(0.3)
	var start_y: float = Units.m_to_px(-width_m * 0.5)
	var end_y: float = Units.m_to_px(width_m * 0.5)
	var half_thickness: float = Units.m_to_px(thickness_m * 0.5)
	for row: int in range(1, rows):
		var y: float = lerpf(start_y, end_y, float(row) / float(rows))
		draw_line(Vector2(-half_thickness, y), Vector2(half_thickness, y), line_color, 1.0)


func _draw_gate(color: Color) -> void:
	_draw_panel(Rect2(-thickness_m * 0.5, -width_m * 0.5, thickness_m, width_m), color, false)
	var bars: int = maxi(3, int(roundf(width_m / 0.25)))
	var half_thickness: float = Units.m_to_px(thickness_m * 0.5)
	var start_y: float = Units.m_to_px(-width_m * 0.5)
	var end_y: float = Units.m_to_px(width_m * 0.5)
	for bar: int in range(bars):
		var y: float = lerpf(start_y, end_y, float(bar) / float(maxi(bars - 1, 1)))
		draw_line(Vector2(-half_thickness, y), Vector2(half_thickness, y), color, 1.0)


func _draw_archway(color: Color) -> void:
	var half_width: float = width_m * 0.5
	var post: float = maxf(thickness_m, 0.15)
	_draw_panel(Rect2(-thickness_m * 0.5, -half_width, thickness_m, post), color, true)
	_draw_panel(
		Rect2(-thickness_m * 0.5, half_width - post, thickness_m, post), color, true
	)


func _draw_panel(rect_m: Rect2, color: Color, filled: bool) -> void:
	var rect_px := Rect2(Units.to_px(rect_m.position), Units.to_px(rect_m.size))
	if filled:
		draw_rect(rect_px, color, true)
		return
	draw_rect(rect_px, color, false, 1.0)


func _draw_editor_marker() -> void:
	var start := Vector2(Units.m_to_px(thickness_m * 0.5), 0.0)
	var tip := Vector2(Units.m_to_px(thickness_m * 0.5 + 0.45), 0.0)
	var wing: float = 0.12
	draw_line(start, tip, EDITOR_NORMAL_COLOR, 1.5)
	var wing_px: float = Units.m_to_px(wing)
	draw_colored_polygon(
		PackedVector2Array(
			[
				tip,
				tip + Vector2(-wing_px, -wing_px),
				tip + Vector2(-wing_px, wing_px),
			]
		),
		EDITOR_NORMAL_COLOR
	)


func _draw_editor_label() -> void:
	if label.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var baseline_y: float = Units.m_to_px(-width_m * 0.5) - 4.0
	draw_string(
		font,
		Vector2(-EDITOR_LABEL_WIDTH_PX * 0.5, baseline_y),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		EDITOR_LABEL_WIDTH_PX,
		EDITOR_LABEL_SIZE,
		EDITOR_LABEL_COLOR
	)


func _find_map() -> MapLoader:
	var node: Node = get_parent()
	while node != null:
		if node is MapLoader:
			return node as MapLoader
		var candidate: MapLoader = node.get_node_or_null("Map") as MapLoader
		if candidate != null:
			return candidate
		node = node.get_parent()
	return null


func _ring_to_m(ring_px: PackedVector2Array) -> PackedVector2Array:
	var ring_m := PackedVector2Array()
	for point_px: Vector2 in ring_px:
		ring_m.append(Units.to_m(point_px))
	return ring_m


func _bounds_of(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds
