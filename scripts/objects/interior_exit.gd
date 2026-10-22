class_name InteriorExit
extends Area2D
## Exit door inside an interior; asks the enclosing Interior to let the actor out.

var _interior: Interior = null


func _ready() -> void:
	# find the enclosing Interior ancestor
	var parent: Node2D = get_parent()
	while parent != null:
		if parent is Interior:
			_interior = parent as Interior
			break
		parent = parent.get_parent()
	if _interior == null:
		push_warning("InteriorExit: no enclosing Interior ancestor; the exit is disabled.")
		return
	# connect to the interior's exit signal if not connected
	if not _interior.exit_requested.is_connected(_on_interior_exit_requested):
		_interior.exit_requested.connect(_on_interior_exit_requested)


func _on_interior_exit_requested(actor: Entity) -> void:
	_exit_actor(actor)


func _exit_actor(actor: Entity) -> void:
	if _interior == null:
		return
	_interior.request_exit(actor)
	queue_free()
