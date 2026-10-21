class_name InteriorExit
extends Node2D
## Exit door inside an interior; asks the enclosing Interior to let the actor out.

const DOOR_LENGTH_M: float = 1.2
const DOOR_THICKNESS_M: float = 0.3
const DOOR_COLOR: Color = Color(0.35, 0.55, 0.9, 0.9)
const EXIT_PROMPT: String = "Exit"

var _interactable: Interactable = null
var _interior: Interior = null


func _ready() -> void:
	_interior = _find_interior()
	if _interior == null:
		push_warning("InteriorExit: no enclosing Interior ancestor; the exit is disabled.")
	_interactable = get_node_or_null("Interactable") as Interactable
	if _interactable == null:
		_interactable = Interactable.new()
		add_child(_interactable)
	_interactable.prompt_text = EXIT_PROMPT
	_interactable.interacted.connect(_on_interacted)
	queue_redraw()


func _find_interior() -> Interior:
	var node: Node = get_parent()
	while node != null:
		var interior := node as Interior
		if interior != null:
			return interior
		node = node.get_parent()
	return null


func _on_interacted(actor: Entity) -> void:
	if _interior == null:
		return
	_interior.request_exit(actor)


func _draw() -> void:
	var half_length := Vector2(Units.m_to_px(DOOR_LENGTH_M * 0.5), 0.0)
	var half_thickness := Vector2(0.0, Units.m_to_px(DOOR_THICKNESS_M * 0.5))
	draw_colored_polygon(
		PackedVector2Array([
			-half_length - half_thickness,
			half_length - half_thickness,
			half_length + half_thickness,
			-half_length + half_thickness,
		]),
		DOOR_COLOR
	)
