class_name Entrance
extends Node2D
## A door on a building footprint: lock/schedule availability and interior entry.

const DOOR_LENGTH_M: float = 1.2
const DOOR_THICKNESS_M: float = 0.3
const OPEN_COLOR: Color = Color(0.25, 0.7, 0.35, 0.9)
const CLOSED_COLOR: Color = Color(0.6, 0.6, 0.6, 0.9)
const LOCKED_COLOR: Color = Color(0.85, 0.3, 0.25, 0.9)
const CLOSED_TEXT_FORMAT: String = "Closed · opens %s"

@onready var _interactable: Area2D = $Interactable

## Set by EntranceSpawner before the node enters the tree.
var data: Resource = null
var _is_open: bool = true


func _ready() -> void:
	if data == null:
		push_warning("Entrance: no EntranceData assigned; the door is inert.")
		return
	_interactable.set("prompt_text", data.get_prompt_text()) if data != null else null
	_interactable.interacted.connect(_on_interacted)
	GameClock.minute_changed.connect(_refresh_availability)
	_refresh_availability()


func _refresh_availability() -> void:
	if data == null:
		return
	var weekday: int = GameClock.get_weekday()
	var hour: float = GameClock.get_hour_float()
	_is_open = data.is_open(weekday, hour)
	if data.locked:
		_interactable.set_available(false, "Locked")
	elif not _is_open:
		_interactable.set_available(false, CLOSED_TEXT_FORMAT % data.next_opening_text(weekday, hour))
	else:
		_interactable.set_available(true)
	queue_redraw()


func _on_interacted(actor: Entity) -> void:
	var im := get_node_or_null("/root/InteriorManager")
	if im == null:
		for node in get_tree().get_nodes_in_group("interior_manager"):
			im = node
			break
	if im == null:
		push_warning("Entrance: no InteriorManager in the scene; cannot enter.")
		return
	if im.has_method("enter"):
		im.call("enter", self, actor)


func _draw() -> void:
	if data == null or data.normal.length_squared() <= 0.0:
		return
	var color: Color = OPEN_COLOR
	if data.locked:
		color = LOCKED_COLOR
	elif not _is_open:
		color = CLOSED_COLOR
	var half_length: Vector2 = data.normal.orthogonal() * Units.m_to_px(DOOR_LENGTH_M * 0.5)
	var half_thickness: Vector2 = data.normal * Units.m_to_px(DOOR_THICKNESS_M * 0.5)
	draw_colored_polygon(
		PackedVector2Array([
			-half_length - half_thickness,
			half_length - half_thickness,
			half_length + half_thickness,
			-half_length + half_thickness,
		]),
		color
	)
