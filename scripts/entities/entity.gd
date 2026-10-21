class_name Entity
extends CharacterBody2D
## Shared body for the player and NPCs. Behavior lives in an EntityController.

const COLLISION_RADIUS_M: float = 0.3
const TURN_RATE: float = 12.0
const TERRAIN_SAMPLE_INTERVAL_S: float = 0.25
const TERRAIN_SAMPLE_DISTANCE_M: float = 1.0

@export var data: EntityData = null
@export var speed_multiplier: float = 1.0
## Terrain speed table; falls back to the shared TerrainRules default when null.
@export var terrain_rules: TerrainRules = null

var controller: EntityController = null
var facing: Vector2 = Vector2.DOWN
## Terrain under this entity; refreshed at most every TERRAIN_SAMPLE_INTERVAL_S.
var current_terrain: TerrainSample = null
## Frozen during screen transitions: velocity zero and the controller is not read.
var locked: bool = false

var _terrain_timer: float = 0.0
var _terrain_speed_factor: float = 1.0
var _last_sample_pos_m: Vector2 = Vector2.ZERO

@onready var _visual: Node2D = $Visual
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = PhysicsLayers.ENTITIES
	collision_mask = PhysicsLayers.WORLD
	_configure_collision_shape()
	current_terrain = TerrainSample.default_sample()
	if controller == null:
		controller = _find_controller()
	if data == null:
		push_warning("Entity: no EntityData assigned; movement is disabled.")
	elif data.id.is_empty():
		EntityRegistry.register(data)
	if _visual != null:
		_visual.rotation = facing.angle()


func set_controller(next_controller: EntityController) -> void:
	if controller == next_controller:
		return
	if controller != null:
		if controller.get_parent() == self:
			remove_child(controller)
		controller.queue_free()
	controller = next_controller
	if controller != null:
		if controller.get_parent() != null:
			controller.get_parent().remove_child(controller)
		add_child(controller)


func set_locked(value: bool) -> void:
	locked = value
	if locked:
		velocity = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if locked:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if controller == null or data == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_update_terrain(delta)
	var move_vector: Vector2 = controller.get_move_vector().limit_length(1.0)
	if move_vector != Vector2.ZERO:
		facing = move_vector.normalized()
		if _visual != null:
			_visual.rotation = lerp_angle(
				_visual.rotation,
				facing.angle(),
				minf(1.0, delta * TURN_RATE)
			)
	var speed_mps: float = data.run_speed_mps if controller.wants_run() else data.walk_speed_mps
	velocity = move_vector * Units.m_to_px(speed_mps * speed_multiplier * _terrain_speed_factor)
	move_and_slide()


## Samples the terrain grid at most every TERRAIN_SAMPLE_INTERVAL_S, or once per meter moved.
func _update_terrain(delta: float) -> void:
	_terrain_timer -= delta
	var position_m := Vector2(Units.px_to_m(global_position.x), Units.px_to_m(global_position.y))
	if _terrain_timer > 0.0 and position_m.distance_to(_last_sample_pos_m) < TERRAIN_SAMPLE_DISTANCE_M:
		return
	_terrain_timer = TERRAIN_SAMPLE_INTERVAL_S
	_last_sample_pos_m = position_m
	var query: TerrainQuery = TerrainQuery.active
	var sample: TerrainSample = TerrainSample.default_sample() if query == null else query.sample(position_m)
	current_terrain = sample
	var rules: TerrainRules = terrain_rules if terrain_rules != null else TerrainRules.shared_default()
	_terrain_speed_factor = rules.get_speed_factor(sample)


func _configure_collision_shape() -> void:
	if _collision_shape == null:
		return
	var circle := _collision_shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		_collision_shape.shape = circle
	circle.radius = Units.m_to_px(COLLISION_RADIUS_M)


func _find_controller() -> EntityController:
	for child: Node in get_children():
		if child is EntityController:
			return child as EntityController
	return null
