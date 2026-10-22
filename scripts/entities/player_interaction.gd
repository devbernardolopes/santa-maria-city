class_name PlayerInteraction
extends Area2D
## Player-side sensor: tracks overlapping Interactables, picks the best target, polls the action.

signal target_changed(target: Interactable)
signal message(text: String)

const RADIUS_M: float = 1.6
const FRONT_BONUS_M: float = 0.5
const FRONT_DOT_THRESHOLD: float = 0.5

@onready var _entity: Entity = get_parent() as Entity

var _overlapping: Array[Interactable] = []
var _current: Interactable = null
var _current_prompt: String = ""
var _active: bool = true


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.INTERACTABLES
	monitorable = false
	var shape_node := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = Units.m_to_px(RADIUS_M)
	shape_node.shape = circle
	add_child(shape_node)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


## Disables the sensor while riding a vehicle and clears the current target.
func set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	monitoring = value
	set_physics_process(value)
	if not value:
		_overlapping.clear()
		_set_target(null)


func _physics_process(_delta: float) -> void:
	_prune_invalid()
	if _overlapping.is_empty():
		if _current != null:
			_set_target(null)
		return
	var target := _pick_target()
	if target != _current:
		_set_target(target)
	elif target != null and target.get_prompt() != _current_prompt:
		# Availability changed while the target stayed (schedule/lock refresh).
		_current_prompt = target.get_prompt()
		target_changed.emit(target)
	if _current == null or _entity == null or _entity.locked:
		return
	if Input.is_action_just_pressed("interact"):
		_current.interact(_entity)


func _set_target(target: Interactable) -> void:
	if _current != null and is_instance_valid(_current) and _current.rejected.is_connected(_on_rejected):
		_current.rejected.disconnect(_on_rejected)
	_current = target
	_current_prompt = ""
	if _current != null and is_instance_valid(_current):
		_current.rejected.connect(_on_rejected)
		_current_prompt = _current.get_prompt()
	target_changed.emit(_current)


## Smallest distance in meters, minus FRONT_BONUS_M for targets roughly in front of the entity.
func _pick_target() -> Interactable:
	if _entity == null:
		return null
	var best: Interactable = null
	var best_score: float = INF
	for target: Interactable in _overlapping:
		if target == null or not is_instance_valid(target):
			continue
		var delta_m := Vector2(
			Units.px_to_m(target.global_position.x - _entity.global_position.x),
			Units.px_to_m(target.global_position.y - _entity.global_position.y)
		)
		var score: float = delta_m.length()
		if score > 0.001 and _entity.facing != Vector2.ZERO:
			if delta_m.normalized().dot(_entity.facing) > FRONT_DOT_THRESHOLD:
				score -= FRONT_BONUS_M
		if score < best_score:
			best_score = score
			best = target
	return best


func _prune_invalid() -> void:
	for index: int in range(_overlapping.size() - 1, -1, -1):
		var target: Interactable = _overlapping[index]
		if target == null or not is_instance_valid(target):
			_overlapping.remove_at(index)


func _on_area_entered(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable != null and not _overlapping.has(interactable):
		_overlapping.append(interactable)


func _on_area_exited(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable != null:
		_overlapping.erase(interactable)


func _on_rejected(_actor: Entity, text: String) -> void:
	if not text.is_empty():
		message.emit(text)
