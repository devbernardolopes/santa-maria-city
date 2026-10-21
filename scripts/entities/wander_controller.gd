class_name WanderController
extends EntityController
## Debug NPC controller: pauses, picks a random direction, and sometimes runs.

const MIN_INTERVAL_S: float = 2.0
const MAX_INTERVAL_S: float = 5.0
const STAND_CHANCE: float = 0.25
const RUN_CHANCE: float = 0.2

@export var random_seed: int = 0

var _rng := RandomNumberGenerator.new()
var _direction: Vector2 = Vector2.ZERO
var _running: bool = false
var _decision_time: float = 0.0


func _ready() -> void:
	if random_seed == 0:
		random_seed = randi()
	_rng.seed = random_seed
	_choose_direction()


func _process(delta: float) -> void:
	_decision_time -= delta
	if _decision_time <= 0.0:
		_choose_direction()


func get_move_vector() -> Vector2:
	return _direction


func wants_run() -> bool:
	return _running


func _choose_direction() -> void:
	_decision_time = _rng.randf_range(MIN_INTERVAL_S, MAX_INTERVAL_S)
	if _rng.randf() < STAND_CHANCE:
		_direction = Vector2.ZERO
		_running = false
		return
	_direction = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
	_running = _rng.randf() < RUN_CHANCE
