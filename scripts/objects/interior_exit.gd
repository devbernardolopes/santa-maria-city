class_name InteriorExit
extends Interactable
## Exit door inside an interior; asks the enclosing Interior to let the actor out.

const EXIT_TEXT: String = "Exit"
const EXIT_WIDTH_M: float = 1.2
const EXIT_THICKNESS_M: float = 0.18
const EXIT_COLOR: Color = Color(0.6, 0.35, 0.2, 0.95)

var _interior: Interior = null


func _ready() -> void:
	super._ready()
	prompt_text = EXIT_TEXT
	set_radius_m(1.0)
	interacted.connect(_on_interacted)
	var parent: Node = get_parent()
	while parent != null:
		if parent is Interior:
			_interior = parent as Interior
			break
		parent = parent.get_parent()
	if _interior == null:
		push_warning("InteriorExit: no enclosing Interior ancestor; the exit is disabled.")


func get_interior() -> Interior:
	return _interior


func _on_interacted(actor: Entity) -> void:
	if _interior == null:
		return
	_interior.request_exit(actor)


func _draw() -> void:
	var half_width: float = Units.m_to_px(EXIT_WIDTH_M * 0.5)
	var half_thickness: float = Units.m_to_px(EXIT_THICKNESS_M * 0.5)
	draw_rect(
		Rect2(-half_width, -half_thickness, half_width * 2.0, half_thickness * 2.0),
		EXIT_COLOR,
		true
	)
