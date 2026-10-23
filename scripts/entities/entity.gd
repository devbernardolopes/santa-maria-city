class_name Entity
extends CharacterBody2D
## Shared body for the player and NPCs. Behavior lives in an EntityController.

## Emitted when the entity walks into a body it is too weak to push.
signal push_rejected(target: Node, required_strength: int)

const COLLISION_RADIUS_M: float = 0.3
const TURN_RATE: float = 12.0
const TERRAIN_SAMPLE_INTERVAL_S: float = 0.25
const TERRAIN_SAMPLE_DISTANCE_M: float = 1.0
## How aligned the movement intent must be with the contact normal to push.
const PUSH_INTENT_DOT: float = 0.25
const PUSH_REJECT_INTERVAL_MS: int = 1500
## Ground friction that bleeds off momentum inherited from a moving vehicle, in m/s².
const INERTIA_DECELERATION_MPS2: float = 8.0
## Inherited speed above which the controller is ignored (the entity is staggered).
const INERTIA_CONTROL_SPEED_MPS: float = 1.0
const INERTIA_STOP_SPEED_MPS: float = 0.05

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
## Hidden and physics-disabled while seated in a vehicle.
var riding: bool = false

var _terrain_timer: float = 0.0
var _terrain_speed_factor: float = 1.0
var _last_sample_pos_m: Vector2 = Vector2.ZERO
var _last_push_reject_target: Node = null
var _last_push_reject_msec: int = -PUSH_REJECT_INTERVAL_MS
## Momentum inherited from a moving vehicle, in m/s; decays with ground friction.
var _inertia_velocity_mps: Vector2 = Vector2.ZERO

@onready var _visual: Node2D = $Visual
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = PhysicsLayers.ENTITIES
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.VEHICLES
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
		_inertia_velocity_mps = Vector2.ZERO


## Seated in a vehicle: hidden, physics off, and no collision until released.
func set_riding(value: bool) -> void:
	riding = value
	visible = not value
	set_physics_process(not value)
	collision_layer = 0 if value else PhysicsLayers.ENTITIES
	collision_mask = 0 if value else PhysicsLayers.WORLD | PhysicsLayers.VEHICLES
	if value:
		velocity = Vector2.ZERO
		_inertia_velocity_mps = Vector2.ZERO


func get_speed_mps() -> float:
	return Units.px_to_m(velocity.length())


func get_velocity_mps() -> Vector2:
	return Units.to_m(velocity)


## D&D ability score; average when the entity has no data resource.
func get_strength() -> int:
	return data.strength if data != null else 10


## Inherited momentum (world space, m/s) that decays with ground friction.
func apply_inertia(velocity_mps: Vector2) -> void:
	_inertia_velocity_mps = velocity_mps


## Momentum still being bled off; zero once the entity is fully under control.
func get_inertia_velocity_mps() -> Vector2:
	return _inertia_velocity_mps


## True while inherited momentum is high enough to override the controller.
func is_staggered() -> bool:
	return _inertia_velocity_mps.length() > INERTIA_CONTROL_SPEED_MPS


func _physics_process(delta: float) -> void:
	if locked:
		velocity = Vector2.ZERO
		_inertia_velocity_mps = Vector2.ZERO
		move_and_slide()
		return
	if controller == null or data == null:
		velocity = Units.to_px(_inertia_velocity_mps)
		move_and_slide()
		_decay_inertia(delta)
		return
	_update_terrain(delta)
	var move_mode: EntityController.MovementMode = controller.movement_mode
	if move_mode == EntityController.MovementMode.RELATIVE:
		_resolve_relative(delta)
	else:
		_resolve_omni(delta)
	_decay_inertia(delta)


func _resolve_omni(delta: float) -> void:
	var move_vector: Vector2 = Vector2.ZERO
	if not is_staggered():
		move_vector = controller.get_move_vector().limit_length(1.0)
	if move_vector != Vector2.ZERO:
		facing = move_vector.normalized()
		if _visual != null:
			_visual.rotation = lerp_angle(
				_visual.rotation, facing.angle(), minf(1.0, delta * TURN_RATE)
			)
	var speed_mps: float = data.run_speed_mps if controller.wants_run() else data.walk_speed_mps
	velocity = (
		move_vector * Units.m_to_px(speed_mps * speed_multiplier * _terrain_speed_factor)
		+ Units.to_px(_inertia_velocity_mps)
	)
	move_and_slide()
	_push_contacts(move_vector)


func _resolve_relative(delta: float) -> void:
	var intent: Vector2 = Vector2.ZERO
	if not is_staggered():
		intent = controller.get_move_intent().limit_length(1.0)
	var turn_input: float = intent.x
	var throttle_input: float = intent.y
	if absf(turn_input) > 0.001:
		var turn_rate: float = controller.turn_rate_rad_s
		if turn_rate < 0.0:
			turn_rate = 0.0
		facing = facing.rotated(turn_input * turn_rate * delta)
	if _visual != null and (absf(turn_input) > 0.001 or absf(throttle_input) > 0.001):
		_visual.rotation = lerp_angle(
			_visual.rotation, facing.angle(), minf(1.0, delta * TURN_RATE)
		)
	var speed_mps: float = data.run_speed_mps if controller.wants_run() else data.walk_speed_mps
	var move_speed_factor: float = 1.0
	if throttle_input < 0.0:
		var reverse_factor: float = controller.reverse_speed_factor
		if reverse_factor < 0.0:
			reverse_factor = 0.0
		move_speed_factor = reverse_factor
	var throttle_magnitude: float = absf(throttle_input)
	var move_vector: Vector2 = facing * throttle_input
	velocity = (
		move_vector
		* Units.m_to_px(speed_mps * speed_multiplier * _terrain_speed_factor * move_speed_factor)
		+ Units.to_px(_inertia_velocity_mps)
	)
	move_and_slide()
	_push_contacts(move_vector)


## Bleeds off inherited momentum at ground-friction rate, so a body thrown from a
## moving vehicle is displaced by v²/(2a) before it comes to rest.
func _decay_inertia(delta: float) -> void:
	if _inertia_velocity_mps.is_zero_approx():
		return
	_inertia_velocity_mps = _inertia_velocity_mps.move_toward(
		Vector2.ZERO, INERTIA_DECELERATION_MPS2 * delta
	)
	if _inertia_velocity_mps.length() < INERTIA_STOP_SPEED_MPS:
		_inertia_velocity_mps = Vector2.ZERO


## Pushes vehicles the entity walks into, if its Strength covers their effective load.
## Kinematic bodies never push each other, so this contact check is the only path that
## lets an entity move a parked vehicle.
func _push_contacts(intent: Vector2) -> void:
	if data == null or intent.length_squared() <= 0.0001:
		return
	var intent_dir: Vector2 = intent.normalized()
	for index: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(index)
		if collision == null:
			continue
		var vehicle: Vehicle = collision.get_collider() as Vehicle
		if vehicle == null:
			continue
		var into: Vector2 = -collision.get_normal()
		if into.length_squared() <= 0.0001:
			continue
		into = into.normalized()
		if intent_dir.dot(into) < PUSH_INTENT_DOT:
			continue
		if not vehicle.is_pushable() or vehicle.is_occupied() or vehicle.locked:
			continue
		var load_kg: float = vehicle.get_push_load_kg()
		if not PushRules.can_push(data.strength, load_kg):
			_report_push_rejected(vehicle, vehicle.get_required_push_strength())
			continue
		vehicle.apply_push(self, into)


## Emits push_rejected at most once per target per interval.
func _report_push_rejected(target: Node, required_strength: int) -> void:
	var now: int = Time.get_ticks_msec()
	if target == _last_push_reject_target and now - _last_push_reject_msec < PUSH_REJECT_INTERVAL_MS:
		return
	_last_push_reject_target = target
	_last_push_reject_msec = now
	push_rejected.emit(target, required_strength)


## Samples the terrain grid at most every TERRAIN_SAMPLE_INTERVAL_S, or once per meter moved.
func _update_terrain(delta: float) -> void:
	_terrain_timer -= delta
	var position_m := Vector2(Units.px_to_m(global_position.x), Units.px_to_m(global_position.y))
	if (
		_terrain_timer > 0.0
		and position_m.distance_to(_last_sample_pos_m) < TERRAIN_SAMPLE_DISTANCE_M
	):
		return
	_terrain_timer = TERRAIN_SAMPLE_INTERVAL_S
	_last_sample_pos_m = position_m
	var query: TerrainQuery = TerrainQuery.active
	var sample: TerrainSample = (
		TerrainSample.default_sample() if query == null else query.sample(position_m)
	)
	current_terrain = sample
	var rules: TerrainRules = (
		terrain_rules if terrain_rules != null else TerrainRules.shared_default()
	)
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
