class_name Vehicle
extends CharacterBody2D
## Drivable vehicle body. Handling is an arcade top-down bicycle model.
##
## The node's +X axis is the heading; the visual rotates the north-facing sprite itself.
## Static definition lives in VehicleData, runtime state (health, tires, occupants) here.

signal entered(actor: Entity)
signal exited(actor: Entity)
signal entry_rejected(actor: Entity, reason: String)
signal damaged(amount: float, cause: StringName)
signal destroyed

const TERRAIN_SAMPLE_INTERVAL_S: float = 0.25
const TERRAIN_SAMPLE_DISTANCE_M: float = 1.0
const EXIT_CLEARANCE_M: float = 0.9
const EXIT_CHECK_RADIUS_M: float = 0.35
const IMPACT_COOLDOWN_S: float = 0.4
const REVERSE_ACCELERATION_SCALE: float = 0.6
const MIN_MOVING_SPEED_MPS: float = 0.1
const WATER_SPEED_FACTOR: float = 0.15
const WATER_GRIP_FACTOR: float = 0.2
const INTERACT_RADIUS_PADDING_M: float = 0.5
const MASS_DAMAGE_REFERENCE_KG: float = 1500.0

@export var data: VehicleData = null
@export var controller: VehicleController = null
@export var vehicle_id: StringName = &""
@export var lights_enabled: bool = false

var health: float = 0.0
var occupants: Array[Entity] = []
var wheels: Array[WheelState] = []
## Item instances once the item system exists; store_item() enforces the capacity.
var contents: Array = []
var current_terrain: TerrainSample = null
## Signed forward speed in m/s from the body's actual movement (negative while reversing).
var speed_mps: float = 0.0
## Frozen during transitions: velocity zero and controls are ignored.
var locked: bool = false

var _steer_angle: float = 0.0
var _terrain_timer: float = 0.0
var _terrain_speed_factor: float = 1.0
var _terrain_grip_factor: float = 1.0
var _last_sample_pos_m: Vector2 = Vector2.ZERO
var _impact_cooldown: float = 0.0
## Actual velocity before the last move_and_slide; used for impact damage.
var _pre_move_velocity_mps: Vector2 = Vector2.ZERO

@onready var _visual: VehicleVisual = get_node_or_null("Visual") as VehicleVisual
@onready var _interactable: Interactable = get_node_or_null("Interactable") as Interactable
@onready
var _collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = PhysicsLayers.VEHICLES
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.VEHICLES | PhysicsLayers.ENTITIES
	current_terrain = TerrainSample.default_sample()
	add_to_group(&"vehicles")
	_configure_collision_shape()
	if data == null:
		push_warning("Vehicle: no VehicleData assigned; driving is disabled.")
		return
	if vehicle_id.is_empty():
		vehicle_id = data.id
	health = data.max_health
	lights_enabled = lights_enabled or data.default_lights_enabled
	_setup_wheels()
	if _visual != null:
		_visual.setup(data)
		_visual.set_lights_enabled(lights_enabled)
	if _interactable != null:
		_interactable.prompt_text = "Drive %s" % data.get_display_name()
		_interactable.set_radius_m(_interaction_radius_m())
		_interactable.interacted.connect(_on_interacted)
	_refresh_interactable()
	if controller == null:
		controller = _find_controller()


func _physics_process(delta: float) -> void:
	if data == null:
		return
	if locked:
		velocity = Vector2.ZERO
		speed_mps = 0.0
		move_and_slide()
		return
	_update_terrain(delta)
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	var throttle: float = 0.0
	var steer: float = 0.0
	var handbrake: bool = false
	if not occupants.is_empty() and controller != null:
		throttle = controller.get_throttle()
		steer = controller.get_steer()
		handbrake = controller.wants_handbrake()
	_drive(delta, throttle, steer, handbrake)
	_apply_impact_damage()


## Public entry point used by Interactable and (future) NPC controllers.
func enter(actor: Entity) -> bool:
	var reason: String = get_entry_block_reason(actor)
	if not reason.is_empty():
		entry_rejected.emit(actor, reason)
		return false
	occupants.append(actor)
	actor.set_locked(true)
	actor.set_riding(true)
	actor.global_position = global_position
	_set_player_interaction_active(actor, false)
	_refresh_interactable()
	entered.emit(actor)
	return true


func exit(actor: Entity) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if not occupants.has(actor):
		return false
	occupants.erase(actor)
	var point_m: Vector2 = _find_exit_point_m()
	actor.global_position = Units.to_px(point_m)
	actor.set_riding(false)
	actor.set_locked(false)
	_set_player_interaction_active(actor, true)
	_refresh_interactable()
	exited.emit(actor)
	return true


func get_entry_block_reason(actor: Entity) -> String:
	if data == null:
		return "Not drivable"
	if actor == null or not is_instance_valid(actor):
		return "Unavailable"
	if occupants.has(actor):
		return "Already inside"
	if health <= 0.0:
		return "Wrecked"
	if occupants.size() >= maxi(1, data.seat_count):
		return "Occupied"
	if actor.locked:
		return "Busy"
	return ""


func can_enter(actor: Entity) -> bool:
	return get_entry_block_reason(actor).is_empty()


func is_occupied() -> bool:
	return not occupants.is_empty()


func get_driver() -> Entity:
	return occupants[0] if not occupants.is_empty() else null


func set_controller(next_controller: VehicleController) -> void:
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


func set_lights_enabled(value: bool) -> void:
	lights_enabled = value
	if _visual != null:
		_visual.set_lights_enabled(value)


func damage(amount: float, cause: StringName = &"impact") -> void:
	if data == null or amount <= 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	damaged.emit(amount, cause)
	if health <= 0.0:
		destroyed.emit()


func repair(amount: float) -> void:
	if data == null or amount <= 0.0:
		return
	health = minf(data.max_health, health + amount)
	_refresh_interactable()


func get_health_ratio() -> float:
	if data == null or data.max_health <= 0.0:
		return 0.0
	return clampf(health / data.max_health, 0.0, 1.0)


func get_speed_mps() -> float:
	return absf(speed_mps)


func get_velocity_mps() -> Vector2:
	return Units.to_m(velocity)


func get_wheel_states() -> Array[WheelState]:
	return wheels


func get_wheel_state(index: int) -> WheelState:
	if index < 0 or index >= wheels.size():
		return null
	return wheels[index]


func set_wheel_present(index: int, value: bool) -> void:
	var wheel: WheelState = get_wheel_state(index)
	if wheel != null:
		wheel.present = value


func set_wheel_pressure(index: int, kpa: float) -> void:
	var wheel: WheelState = get_wheel_state(index)
	if wheel != null:
		wheel.pressure_kpa = maxf(0.0, kpa)


## Average grip of every wheel; 1.0 when no layout is authored.
func get_wheel_grip_factor() -> float:
	if wheels.is_empty():
		return 1.0
	var flat_pressure: float = data.flat_tire_pressure_kpa if data != null else 110.0
	var total: float = 0.0
	for wheel: WheelState in wheels:
		total += wheel.get_grip_factor(flat_pressure)
	return total / float(wheels.size())


## Average grip of driven wheels; falls back to all wheels when none are marked driven.
func get_wheel_drive_factor() -> float:
	if wheels.is_empty():
		return 1.0
	var flat_pressure: float = data.flat_tire_pressure_kpa if data != null else 110.0
	var total: float = 0.0
	var count: int = 0
	for wheel: WheelState in wheels:
		if not wheel.is_driven():
			continue
		total += wheel.get_grip_factor(flat_pressure)
		count += 1
	if count == 0:
		for wheel: WheelState in wheels:
			total += wheel.get_grip_factor(flat_pressure)
			count += 1
	return total / float(maxi(1, count))


## Adds an item instance while capacity allows. The item system is not implemented yet.
func store_item(item: Variant) -> bool:
	if data == null or not data.can_store_items:
		return false
	if contents.size() >= data.storage_slots:
		return false
	contents.append(item)
	return true


func take_item(index: int) -> Variant:
	if index < 0 or index >= contents.size():
		return null
	return contents.pop_at(index)


func describe_state() -> String:
	if data == null:
		return "No vehicle data"
	var parts: PackedStringArray = [
		"%d km/h" % int(roundf(get_speed_mps() * 3.6)),
		"%d/%d HP" % [int(roundf(health)), int(roundf(data.max_health))],
	]
	var present: int = 0
	for wheel: WheelState in wheels:
		if wheel.present:
			present += 1
	parts.append("tires %d/%d" % [present, wheels.size()])
	return " · ".join(parts)


## Save hook: position, heading, health, lights, and tire condition.
func get_state() -> Dictionary:
	var position_m: Vector2 = Units.to_m(global_position)
	var wheel_states: Array[Dictionary] = []
	for wheel: WheelState in wheels:
		(
			wheel_states
			. append(
				{
					"present": wheel.present,
					"pressure_kpa": wheel.pressure_kpa,
					"tread": wheel.tread,
				}
			)
		)
	return {
		"id": String(vehicle_id),
		"position_m": [position_m.x, position_m.y],
		"heading_rad": rotation,
		"health": health,
		"lights_enabled": lights_enabled,
		"wheels": wheel_states,
	}


## Invalid fields warn and are skipped; valid ones are applied.
func load_state(state: Dictionary) -> void:
	var position_value: Variant = state.get("position_m")
	if position_value is Array:
		var values: Array = position_value
		if values.size() == 2 and _is_number(values[0]) and _is_number(values[1]):
			global_position = Units.to_px(Vector2(float(values[0]), float(values[1])))
		else:
			push_warning("Vehicle.load_state: 'position_m' must be [x, y]; ignored.")
	var heading_value: Variant = state.get("heading_rad")
	if _is_number(heading_value):
		rotation = wrapf(float(heading_value), -PI, PI)
	elif heading_value != null:
		push_warning("Vehicle.load_state: 'heading_rad' must be a number; ignored.")
	var health_value: Variant = state.get("health")
	if _is_number(health_value) and data != null:
		health = clampf(float(health_value), 0.0, data.max_health)
		_refresh_interactable()
	elif health_value != null:
		push_warning("Vehicle.load_state: 'health' must be a number; ignored.")
	var lights_value: Variant = state.get("lights_enabled")
	if lights_value is bool:
		set_lights_enabled(lights_value)
	var wheels_value: Variant = state.get("wheels")
	if wheels_value is Array:
		var wheel_values: Array = wheels_value
		_load_wheel_states(wheel_values)


func _drive(delta: float, throttle: float, steer: float, handbrake: bool) -> void:
	var forward: Vector2 = Vector2.from_angle(rotation)
	# Use the body's actual motion, not the requested velocity. When the vehicle is
	# pressed against an obstacle, velocity keeps growing while the body does not move.
	var realized_velocity_m: Vector2 = Units.to_m(get_real_velocity())
	var speed_before: float = realized_velocity_m.dot(forward)
	var steer_scale: float = lerpf(
		1.0,
		data.high_speed_steer_factor,
		clampf(absf(speed_before) / maxf(data.max_speed_mps, 1.0), 0.0, 1.0)
	)
	var steer_target: float = steer * deg_to_rad(data.max_steer_deg) * steer_scale
	_steer_angle = move_toward(
		_steer_angle, steer_target, deg_to_rad(data.steer_rate_deg_s) * delta
	)
	if absf(speed_before) > MIN_MOVING_SPEED_MPS:
		var yaw_rate: float = (speed_before / data.get_wheelbase_m()) * tan(_steer_angle)
		rotation = wrapf(rotation + yaw_rate * delta, -PI, PI)
	forward = Vector2.from_angle(rotation)
	var right: Vector2 = forward.orthogonal()
	var forward_speed: float = realized_velocity_m.dot(forward)
	var lateral_speed: float = realized_velocity_m.dot(right)
	forward_speed = _integrate_forward_speed(forward_speed, throttle, delta)
	var grip: float = data.lateral_grip * get_wheel_grip_factor() * _terrain_grip_factor
	if handbrake:
		grip *= data.handbrake_grip_factor
	lateral_speed *= exp(-maxf(grip, 0.05) * delta)
	velocity = (forward * forward_speed + right * lateral_speed) * Units.PX_PER_METER
	_pre_move_velocity_mps = realized_velocity_m
	move_and_slide()
	# Keep the requested velocity in sync with the achieved motion, so a blocked
	# vehicle neither accumulates speed nor keeps triggering impact damage.
	velocity = get_real_velocity()
	speed_mps = Units.to_m(velocity).dot(forward)
	if absf(speed_mps) < MIN_MOVING_SPEED_MPS:
		speed_mps = 0.0


func _integrate_forward_speed(forward_speed: float, throttle: float, delta: float) -> float:
	var drive_factor: float = get_wheel_drive_factor()
	var max_forward: float = data.max_speed_mps * _terrain_speed_factor * drive_factor
	var max_reverse: float = data.max_reverse_speed_mps * _terrain_speed_factor * drive_factor
	var power_scale: float = drive_factor * _terrain_speed_factor
	if throttle > 0.01:
		if forward_speed < -MIN_MOVING_SPEED_MPS:
			forward_speed = move_toward(forward_speed, 0.0, data.brake_mps2 * throttle * delta)
		else:
			var headroom: float = clampf(1.0 - forward_speed / maxf(max_forward, 0.1), 0.0, 1.0)
			forward_speed += data.acceleration_mps2 * throttle * power_scale * headroom * delta
	elif throttle < -0.01:
		if forward_speed > MIN_MOVING_SPEED_MPS:
			forward_speed = move_toward(forward_speed, 0.0, data.brake_mps2 * -throttle * delta)
		else:
			var reverse_scale: float = REVERSE_ACCELERATION_SCALE * -throttle * power_scale
			forward_speed -= data.acceleration_mps2 * reverse_scale * delta
	else:
		forward_speed = move_toward(forward_speed, 0.0, data.engine_braking_mps2 * delta)
	forward_speed = move_toward(forward_speed, 0.0, data.rolling_resistance_mps2 * delta)
	return clampf(forward_speed, -max_reverse, max_forward)


func _update_terrain(delta: float) -> void:
	_terrain_timer -= delta
	var position_m: Vector2 = Units.to_m(global_position)
	if (
		_terrain_timer > 0.0
		and position_m.distance_to(_last_sample_pos_m) < TERRAIN_SAMPLE_DISTANCE_M
	):
		return
	_terrain_timer = TERRAIN_SAMPLE_INTERVAL_S
	_last_sample_pos_m = position_m
	var query: TerrainQuery = TerrainQuery.active
	current_terrain = TerrainSample.default_sample() if query == null else query.sample(position_m)
	var profile: VehicleTerrainProfile = data.terrain_profile
	if profile == null:
		profile = VehicleTerrainProfile.shared_default()
	_terrain_speed_factor = profile.get_speed_factor(current_terrain)
	_terrain_grip_factor = profile.get_grip_factor(current_terrain)
	if TerrainSample.is_water_landuse(current_terrain.category, current_terrain.kind):
		_terrain_speed_factor = WATER_SPEED_FACTOR
		_terrain_grip_factor = WATER_GRIP_FACTOR


func _apply_impact_damage() -> void:
	if data == null or _impact_cooldown > 0.0:
		return
	if _pre_move_velocity_mps.length() <= data.impact_damage_threshold_mps:
		return
	for index: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(index)
		if collision == null:
			continue
		var impact_speed: float = absf(_pre_move_velocity_mps.dot(collision.get_normal()))
		if impact_speed <= data.impact_damage_threshold_mps:
			continue
		var mass_scale: float = clampf(data.get_mass_kg() / MASS_DAMAGE_REFERENCE_KG, 0.5, 3.0)
		var amount: float = impact_speed - data.impact_damage_threshold_mps
		amount *= data.impact_damage_per_mps * mass_scale
		_impact_cooldown = IMPACT_COOLDOWN_S
		damage(amount, &"impact")
		return


func _setup_wheels() -> void:
	wheels.clear()
	if data == null:
		return
	for spec: WheelSpec in data.get_wheels():
		wheels.append(WheelState.new(spec))


func _configure_collision_shape() -> void:
	if _collision_shape == null:
		_collision_shape = CollisionShape2D.new()
		add_child(_collision_shape)
	var capsule: CapsuleShape2D = _collision_shape.shape as CapsuleShape2D
	if capsule == null:
		capsule = CapsuleShape2D.new()
		_collision_shape.shape = capsule
	var width_m: float = data.width_m if data != null else 1.9
	var length_m: float = data.length_m if data != null else 4.5
	capsule.radius = maxf(1.0, Units.m_to_px(width_m) * 0.5)
	capsule.height = maxf(Units.m_to_px(length_m), capsule.radius * 2.0)
	_collision_shape.rotation = PI * 0.5


func _interaction_radius_m() -> float:
	if data == null:
		return 2.0
	return maxf(data.width_m * 0.5, data.length_m * 0.35) + INTERACT_RADIUS_PADDING_M


func _refresh_interactable() -> void:
	if _interactable == null:
		return
	if data == null:
		_interactable.set_available(false, "Not drivable")
	elif health <= 0.0:
		_interactable.set_available(false, "Wrecked")
	elif occupants.size() >= maxi(1, data.seat_count):
		_interactable.set_available(false, "Occupied")
	else:
		_interactable.set_available(true)


func _on_interacted(actor: Entity) -> void:
	enter(actor)


func _set_player_interaction_active(actor: Entity, value: bool) -> void:
	var interaction: Node = actor.get_node_or_null("PlayerInteraction")
	if interaction != null and interaction.has_method("set_active"):
		interaction.call("set_active", value)


func _find_exit_point_m() -> Vector2:
	var origin_m: Vector2 = Units.to_m(global_position)
	var forward: Vector2 = Vector2.from_angle(rotation)
	var right: Vector2 = forward.orthogonal()
	var width_m: float = data.width_m if data != null else 1.9
	var length_m: float = data.length_m if data != null else 4.5
	var side_m: float = width_m * 0.5 + EXIT_CLEARANCE_M
	var back_m: float = length_m * 0.5 + EXIT_CLEARANCE_M
	var candidates: Array[Vector2] = [
		origin_m - right * side_m,
		origin_m + right * side_m,
		origin_m - forward * back_m,
		origin_m + forward * back_m,
	]
	for candidate: Vector2 in candidates:
		if _is_exit_point_clear(candidate):
			return candidate
	return origin_m


func _is_exit_point_clear(point_m: Vector2) -> bool:
	var query: TerrainQuery = TerrainQuery.active
	if query != null:
		var sample: TerrainSample = query.sample(point_m)
		if TerrainSample.is_water_landuse(sample.category, sample.kind):
			return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = Units.m_to_px(EXIT_CHECK_RADIUS_M)
	params.shape = circle
	params.transform = Transform2D(0.0, Units.to_px(point_m))
	params.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.VEHICLES
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var exclude: Array[RID] = [get_rid()]
	params.exclude = exclude
	return space.intersect_shape(params, 1).is_empty()


func _load_wheel_states(values: Array) -> void:
	var count: int = mini(values.size(), wheels.size())
	for index: int in range(count):
		var value: Variant = values[index]
		if not (value is Dictionary):
			continue
		var entry: Dictionary = value
		var wheel: WheelState = wheels[index]
		var present_value: Variant = entry.get("present")
		if present_value is bool:
			wheel.present = present_value
		var pressure_value: Variant = entry.get("pressure_kpa")
		if _is_number(pressure_value):
			wheel.pressure_kpa = maxf(0.0, float(pressure_value))
		var tread_value: Variant = entry.get("tread")
		if _is_number(tread_value):
			wheel.tread = clampf(float(tread_value), 0.0, 1.0)


func _find_controller() -> VehicleController:
	for child: Node in get_children():
		if child is VehicleController:
			return child as VehicleController
	return null


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
