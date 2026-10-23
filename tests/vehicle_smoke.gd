extends Node2D
## Headless vehicle test: data resources, wheels, handling, impact damage, and enter/exit.

const VEHICLE_SCENE: PackedScene = preload("res://scenes/vehicles/vehicle.tscn")
const ENTITY_SCENE: PackedScene = preload("res://scenes/entities/entity.tscn")
const CAR_PATH: String = "res://resources/vehicles/car.tres"
const TRUCK_PATH: String = "res://resources/vehicles/truck.tres"
const VEHICLE_DATA_NAMES: Array[String] = [
	"car",
	"audi",
	"black_viper",
	"taxi",
	"truck",
	"mini_truck",
	"mini_van",
	"ambulance",
	"police",
]
const DRIVE_STEPS: int = 180

var _failures: PackedStringArray = PackedStringArray()


class TestController:
	extends VehicleController

	var throttle_value: float = 0.0

	func get_throttle() -> float:
		return throttle_value


class TestEntityController:
	extends EntityController

	var move_vector: Vector2 = Vector2.ZERO

	func get_move_vector() -> Vector2:
		return move_vector

	func get_move_intent() -> Vector2:
		return move_vector


func _ready() -> void:
	await _run()
	if _failures.is_empty():
		print("VEHICLE SMOKE OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("VEHICLE SMOKE FAIL: %s" % failure)
	get_tree().quit(1)


func _run() -> void:
	_validate_resources()
	_test_wheels()
	_test_terrain_profile()
	_test_push_rules()
	_test_world_scene()
	await _test_spawner()
	await _test_drive_and_impact()
	await _test_blocked_vehicle()
	await _test_enter_exit()
	await _test_parked_idle()
	await _test_exit_does_not_slide()
	await _test_exit_keeps_momentum()
	await _test_exit_inertia()
	await _test_push_strength()
	_test_damage()


func _test_terrain_profile() -> void:
	var profile := VehicleTerrainProfile.create_default()
	var sample := TerrainSample.new()
	sample.category = &"landuse"
	sample.kind = &"grass"
	var grass_grip: float = profile.get_grip_factor(sample)
	if grass_grip >= 1.0:
		_fail("grass does not reduce vehicle grip")
	sample.category = &"landuse"
	sample.kind = &"residential"
	sample.surface = &"asphalt"
	if profile.get_speed_factor(sample) < 0.9:
		_fail("asphalt does not allow full vehicle speed")
	if profile.get_grip_factor(sample) < 0.9:
		_fail("asphalt does not provide full vehicle grip")


func _test_push_rules() -> void:
	var capacities: Dictionary = {
		10: 136.08,
		15: 272.16,
		20: 544.31,
		25: 1088.62,
		30: 2177.24,
	}
	for strength: int in capacities:
		var expected: float = capacities[strength]
		var actual: float = PushRules.push_capacity_kg(strength)
		if absf(actual - expected) > 0.1:
			_fail(
				(
					"push capacity at Str %d is %.2f kg, expected %.2f kg"
					% [strength, actual, expected]
				)
			)
	var car := load(CAR_PATH) as VehicleData
	if car == null:
		_fail("car data missing for the push rules test")
		return
	var car_load: float = car.get_push_load_kg()
	if PushRules.can_push(10, car_load):
		_fail("Strength 10 can push a %.0f kg load" % car_load)
	if PushRules.can_push(26, car_load):
		_fail("Strength 26 can push a %.0f kg load" % car_load)
	if not PushRules.can_push(27, car_load):
		_fail("Strength 27 cannot push a %.0f kg load" % car_load)
	if PushRules.min_strength_for(car_load) != 27:
		_fail("car requires Strength %d instead of 27" % PushRules.min_strength_for(car_load))
	var ambulance := load("res://resources/vehicles/ambulance.tres") as VehicleData
	if ambulance == null:
		_fail("ambulance data missing for the push rules test")
	else:
		var ambulance_required: int = PushRules.min_strength_for(ambulance.get_push_load_kg())
		if ambulance_required <= 30:
			_fail(
				(
					"the %.0f kg ambulance should require more than Strength 30, got %d"
					% [ambulance.get_mass_kg(), ambulance_required]
				)
			)
	var entity_data := EntityData.new()
	entity_data.strength = 10
	if absf(entity_data.get_push_capacity_kg() - 136.08) > 0.1:
		_fail("EntityData does not follow the push capacity curve")
	if entity_data.get_carry_capacity_kg() >= entity_data.get_push_capacity_kg():
		_fail("carrying capacity should be lower than push capacity")


func _test_world_scene() -> void:
	if not ResourceLoader.exists("res://scenes/world/world.tscn"):
		_fail("world scene is missing")
		return
	var scene := load("res://scenes/world/world.tscn") as PackedScene
	if scene == null:
		_fail("world scene does not load")
		return
	var instance := scene.instantiate()
	if instance == null:
		_fail("world scene does not instantiate")
		return
	if not (instance.get_node_or_null("VehicleSpawner") is VehicleSpawner):
		_fail("world scene has no VehicleSpawner node")
	if instance.get_node_or_null("FollowCamera") == null:
		_fail("world scene has no FollowCamera node")
	instance.free()


func _validate_resources() -> void:
	for name: String in VEHICLE_DATA_NAMES:
		var path: String = "res://resources/vehicles/%s.tres" % name
		if not ResourceLoader.exists(path):
			_fail("missing %s" % path)
			continue
		var data := load(path) as VehicleData
		if data == null:
			_fail("%s is not VehicleData" % path)
			continue
		if data.frames.is_empty():
			_fail("%s has no sprite frames" % name)
		if data.length_m <= 0.0 or data.width_m <= 0.0:
			_fail("%s has invalid body dimensions" % name)
		if data.get_wheels().is_empty():
			_fail("%s has no wheels" % name)
		if data.get_mass_kg() <= 0.0:
			_fail("%s has no mass" % name)
		if data.get_push_load_kg() <= 0.0:
			_fail("%s has no push load" % name)
		if data.max_health <= 0.0:
			_fail("%s has no health" % name)
		if data.seat_count < 1:
			_fail("%s has no seats" % name)


func _test_wheels() -> void:
	var truck := load(TRUCK_PATH) as VehicleData
	if truck == null:
		_fail("truck data missing")
		return
	if truck.get_wheel_count() != 6:
		_fail("truck should have 6 wheels, got %d" % truck.get_wheel_count())
	var spec := WheelSpec.new()
	spec.nominal_pressure_kpa = 220.0
	var wheel := WheelState.new(spec)
	var nominal_grip: float = wheel.get_grip_factor(110.0)
	if nominal_grip <= 0.0:
		_fail("nominal tire has no grip")
	wheel.pressure_kpa = 100.0
	if wheel.get_grip_factor(110.0) >= nominal_grip:
		_fail("flat tire does not reduce grip")
	wheel.present = false
	if wheel.get_grip_factor(110.0) != 0.0:
		_fail("missing tire should have zero grip")


func _test_spawner() -> void:
	var root := Node2D.new()
	root.name = "SpawnRoot"
	var objects := Node2D.new()
	objects.name = "Objects"
	root.add_child(objects)
	add_child(root)
	var spawner := VehicleSpawner.new()
	spawner.name = "VehicleSpawner"
	spawner.overlay_path = "user://vehicle_overlay_test.json"
	spawner.debug_fallback_count = 0
	root.add_child(spawner)
	var file := FileAccess.open(spawner.overlay_path, FileAccess.WRITE)
	if file == null:
		_fail("could not write the overlay fixture")
		root.queue_free()
		return
	file.store_string(
		(
			'{"version":1,"vehicles":[{"id":"v_test",'
			+ '"data":"res://resources/vehicles/taxi.tres",'
			+ '"position":[200.0,0.0],"heading_deg":90}]}'
		)
	)
	file.close()
	var spawned: Array[Vehicle] = []
	spawner.vehicle_spawned.connect(func(vehicle: Vehicle) -> void: spawned.append(vehicle))
	await get_tree().physics_frame
	spawner.spawn_vehicles(Vector2.ZERO)
	if spawned.size() != 1:
		_fail("spawner did not spawn the overlay vehicle")
	else:
		var vehicle: Vehicle = spawned[0]
		if vehicle.vehicle_id != &"v_test":
			_fail("spawner did not keep the overlay id")
		if vehicle.data == null or vehicle.data.id != &"taxi":
			_fail("spawner did not apply the overlay data")
		if not is_equal_approx(vehicle.rotation, PI * 0.5):
			_fail("spawner did not apply the overlay heading")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://vehicle_overlay_test.json"))
	root.queue_free()
	await get_tree().process_frame


func _test_drive_and_impact() -> void:
	var vehicle := _spawn_vehicle(CAR_PATH, Vector2.ZERO, 0.0)
	if vehicle == null:
		_fail("could not spawn the test car")
		return
	var actor := _make_actor(Vector2(2.0, 0.0))
	if actor == null:
		_fail("could not create the test driver")
		vehicle.queue_free()
		return
	if not vehicle.enter(actor):
		_fail("could not seat the test driver")
	var controller := TestController.new()
	controller.throttle_value = 1.0
	vehicle.set_controller(controller)
	var wall := _spawn_wall(Vector2(8.0, 0.0))
	var top_speed: float = 0.0
	var damaged: bool = false
	for _step: int in range(DRIVE_STEPS):
		await get_tree().physics_frame
		if not is_instance_valid(vehicle):
			break
		top_speed = maxf(top_speed, vehicle.get_speed_mps())
		if vehicle.health < vehicle.data.max_health:
			damaged = true
			break
	if top_speed < 2.0:
		_fail("vehicle did not accelerate (top speed %.2f m/s)" % top_speed)
	if not damaged:
		_fail("vehicle did not take impact damage")
	var shape_node := vehicle.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not (shape_node.shape is CapsuleShape2D):
		_fail("vehicle collision shape is not a capsule")
	wall.queue_free()
	actor.queue_free()
	vehicle.queue_free()
	await get_tree().process_frame


func _test_blocked_vehicle() -> void:
	var vehicle := _spawn_vehicle(CAR_PATH, Vector2(0.0, 40.0), 0.0)
	if vehicle == null:
		_fail("could not spawn the blocked-vehicle car")
		return
	var actor := _make_actor(Vector2(2.0, 40.0))
	if actor == null:
		_fail("could not create the blocked-vehicle driver")
		vehicle.queue_free()
		return
	if not vehicle.enter(actor):
		_fail("could not seat the blocked-vehicle driver")
	var controller := TestController.new()
	controller.throttle_value = 1.0
	vehicle.set_controller(controller)
	var wall := _spawn_wall(Vector2(8.0, 40.0))
	var damaged: bool = false
	for _step: int in range(DRIVE_STEPS):
		await get_tree().physics_frame
		if vehicle.health < vehicle.data.max_health:
			damaged = true
			break
	if not damaged:
		_fail("blocked vehicle did not take initial impact damage")
	# Keep the throttle held against the wall; the body must stop and stop taking damage.
	for _step: int in range(120):
		await get_tree().physics_frame
	var blocked_speed: float = vehicle.get_speed_mps()
	var health_before: float = vehicle.health
	for _step: int in range(120):
		await get_tree().physics_frame
	var health_after: float = vehicle.health
	print(
		(
			"VEHICLE SMOKE blocked speed: %.3f m/s, health %.1f -> %.1f"
			% [blocked_speed, health_before, health_after]
		)
	)
	if blocked_speed > 0.5:
		_fail("blocked vehicle still reports %.2f m/s" % blocked_speed)
	if health_after < health_before:
		_fail("blocked vehicle kept losing health (%.1f -> %.1f)" % [health_before, health_after])
	wall.queue_free()
	actor.queue_free()
	vehicle.queue_free()
	await get_tree().process_frame


func _test_enter_exit() -> void:
	await get_tree().physics_frame
	var vehicle := _spawn_vehicle(CAR_PATH, Vector2(40.0, 0.0), 0.0)
	if vehicle == null:
		_fail("could not spawn the enter/exit car")
		return
	var actor := _make_actor(Vector2(38.0, 0.0))
	if actor == null:
		_fail("could not instantiate the entity scene")
		vehicle.queue_free()
		return
	await get_tree().physics_frame
	var reason: String = vehicle.get_entry_block_reason(actor)
	if not reason.is_empty():
		_fail("vehicle blocked entry: %s" % reason)
	if not vehicle.enter(actor):
		_fail("enter() returned false")
	if vehicle.occupants.size() != 1:
		_fail("occupant was not recorded")
	if not actor.riding or actor.visible:
		_fail("actor was not hidden while riding")
	if actor.collision_layer != 0:
		_fail("riding actor still has a collision layer")
	if not vehicle.exit(actor):
		_fail("exit() returned false")
	if not vehicle.occupants.is_empty():
		_fail("occupants were not cleared on exit")
	if actor.riding or not actor.visible:
		_fail("actor was not restored after exit")
	if actor.collision_layer != PhysicsLayers.ENTITIES:
		_fail("actor collision layer was not restored")
	var distance_m: float = Units.to_m(actor.global_position).distance_to(
		Units.to_m(vehicle.global_position)
	)
	if distance_m < 0.5:
		_fail("exit point is inside the vehicle")
	actor.queue_free()
	vehicle.queue_free()
	await get_tree().process_frame


func _test_parked_idle() -> void:
	var vehicle := _spawn_vehicle(CAR_PATH, Vector2(0.0, 120.0), 0.4)
	if vehicle == null:
		_fail("could not spawn the parked car")
		return
	await get_tree().physics_frame
	var start_px: Vector2 = vehicle.global_position
	for _step: int in range(300):
		await get_tree().physics_frame
	var drift_m: float = Units.px_to_m(vehicle.global_position.distance_to(start_px))
	if drift_m > 0.001:
		_fail("parked vehicle drifted %.4f m" % drift_m)
	if vehicle.get_velocity_mps().length() > 0.0001:
		_fail("parked vehicle kept a physics velocity")
	if not is_zero_approx(vehicle.get_speed_mps()):
		_fail("parked vehicle reports a non-zero speed")
	vehicle.queue_free()
	await get_tree().process_frame


func _test_exit_does_not_slide() -> void:
	var vehicle := _spawn_vehicle(CAR_PATH, Vector2(0.0, 200.0), 0.0)
	if vehicle == null:
		_fail("could not spawn the exit-slide car")
		return
	var actor := _make_actor(Vector2(2.0, 200.0))
	if actor == null:
		_fail("could not create the exit-slide driver")
		vehicle.queue_free()
		return
	if not vehicle.enter(actor):
		_fail("could not seat the exit-slide driver")
		return
	var controller := TestController.new()
	controller.throttle_value = 1.0
	vehicle.set_controller(controller)
	var start_px: Vector2 = vehicle.global_position
	for _step: int in range(90):
		await get_tree().physics_frame
	controller.throttle_value = 0.0
	for _step: int in range(300):
		await get_tree().physics_frame
	if Units.px_to_m(vehicle.global_position.distance_to(start_px)) < 1.0:
		_fail("exit-slide car did not drive before stopping")
	if vehicle.get_speed_mps() > 0.001:
		_fail(
			(
				"exit-slide car did not stop before the driver left (%.3f m/s)"
				% vehicle.get_speed_mps()
			)
		)
	if not vehicle.exit(actor):
		_fail("exit() failed for the exit-slide car")
		return
	var parked_px: Vector2 = vehicle.global_position
	for _step: int in range(300):
		await get_tree().physics_frame
	var drift_m: float = Units.px_to_m(vehicle.global_position.distance_to(parked_px))
	if drift_m > 0.001:
		_fail("car slid %.4f m after the driver exited" % drift_m)
	actor.queue_free()
	vehicle.queue_free()
	await get_tree().process_frame


func _test_exit_keeps_momentum() -> void:
	var vehicle := _spawn_vehicle(CAR_PATH, Vector2(0.0, 400.0), 0.0)
	if vehicle == null:
		_fail("could not spawn the momentum car")
		return
	var actor := _make_actor(Vector2(2.0, 400.0))
	if actor == null:
		_fail("could not create the momentum driver")
		vehicle.queue_free()
		return
	if not vehicle.enter(actor):
		_fail("could not seat the momentum driver")
		return
	var controller := TestController.new()
	controller.throttle_value = 1.0
	vehicle.set_controller(controller)
	for _step: int in range(90):
		await get_tree().physics_frame
	var exit_speed: float = vehicle.get_speed_mps()
	if exit_speed < 2.0:
		_fail("momentum car did not reach speed before exit (%.2f m/s)" % exit_speed)
	var exit_px: Vector2 = vehicle.global_position
	if not vehicle.exit(actor):
		_fail("exit() failed for the momentum car")
		return
	if vehicle.get_velocity_mps().length() < 1.0:
		_fail("vehicle lost its velocity the moment the driver exited")
	for _step: int in range(30):
		await get_tree().physics_frame
	var coasted_m: float = Units.px_to_m(vehicle.global_position.distance_to(exit_px))
	if coasted_m < 0.3:
		_fail("vehicle stopped instantly after the driver exited (%.3f m)" % coasted_m)
	if vehicle.global_position.x < exit_px.x:
		_fail("coasting vehicle moved against its heading")
	var coast_speed: float = vehicle.get_speed_mps()
	if coast_speed >= exit_speed:
		_fail("coasting vehicle did not lose speed (%.2f -> %.2f m/s)" % [exit_speed, coast_speed])
	var stopped: bool = false
	for _step: int in range(600):
		await get_tree().physics_frame
		if vehicle.get_velocity_mps().length() < 0.001:
			stopped = true
			break
	if not stopped:
		_fail("coasting vehicle never came to a stop")
	var settled_px: Vector2 = vehicle.global_position
	for _step: int in range(60):
		await get_tree().physics_frame
	if Units.px_to_m(vehicle.global_position.distance_to(settled_px)) > 0.001:
		_fail("coasting vehicle moved again after stopping")
	actor.queue_free()
	vehicle.queue_free()
	await get_tree().process_frame


func _test_exit_inertia() -> void:
	var slow_slide_m: float = await _measure_exit_slide(5.0, 480.0)
	var fast_slide_m: float = await _measure_exit_slide(9.0, 560.0)
	if slow_slide_m < 0.8:
		_fail("exiting at ~20 km/h did not displace the entity (%.2f m)" % slow_slide_m)
	if fast_slide_m <= slow_slide_m:
		_fail(
			(
				"a faster exit should displace farther (%.2f m vs %.2f m)"
				% [fast_slide_m, slow_slide_m]
			)
		)
	if fast_slide_m < slow_slide_m * 2.0:
		_fail(
			(
				"exit displacement does not scale with momentum (%.2f m vs %.2f m)"
				% [fast_slide_m, slow_slide_m]
			)
		)


## Drives a car to target_speed_mps, exits, and returns how far the rider slid.
func _measure_exit_slide(target_speed_mps: float, y_m: float) -> float:
	var vehicle := _spawn_vehicle(CAR_PATH, Vector2(0.0, y_m), 0.0)
	if vehicle == null:
		_fail("could not spawn the inertia car")
		return 0.0
	var actor := _make_actor(Vector2(2.0, y_m))
	if actor == null:
		_fail("could not create the inertia driver")
		vehicle.queue_free()
		return 0.0
	if not vehicle.enter(actor):
		_fail("could not seat the inertia driver")
		return 0.0
	var controller := TestController.new()
	controller.throttle_value = 1.0
	vehicle.set_controller(controller)
	for _step: int in range(240):
		await get_tree().physics_frame
		if vehicle.get_speed_mps() >= target_speed_mps:
			break
	var exit_speed: float = vehicle.get_speed_mps()
	if exit_speed < target_speed_mps:
		_fail("inertia car did not reach %.1f m/s (%.2f m/s)" % [target_speed_mps, exit_speed])
	if not vehicle.exit(actor):
		_fail("exit() failed for the inertia car")
		return 0.0
	var inherited: float = actor.get_inertia_velocity_mps().length()
	if inherited < exit_speed * 0.9:
		_fail("entity inherited %.2f m/s instead of %.2f m/s" % [inherited, exit_speed])
	var start_px: Vector2 = actor.global_position
	for _step: int in range(240):
		await get_tree().physics_frame
	var slide_m: float = Units.px_to_m(actor.global_position.distance_to(start_px))
	if actor.global_position.x < start_px.x:
		_fail("entity slid against the vehicle heading")
	var settled_px: Vector2 = actor.global_position
	for _step: int in range(60):
		await get_tree().physics_frame
	if Units.px_to_m(actor.global_position.distance_to(settled_px)) > 0.001:
		_fail("entity kept sliding after it stopped")
	actor.queue_free()
	vehicle.queue_free()
	await get_tree().process_frame
	return slide_m


func _test_push_strength() -> void:
	var vehicle := _spawn_vehicle(CAR_PATH, Vector2(0.0, 280.0), 0.0)
	if vehicle == null:
		_fail("could not spawn the push-test car")
		return
	var actor := _make_actor(Vector2(-3.0, 280.0))
	if actor == null:
		_fail("could not create the push-test actor")
		vehicle.queue_free()
		return
	actor.data.strength = 10
	var mover := TestEntityController.new()
	mover.move_vector = Vector2.RIGHT
	actor.set_controller(mover)
	await get_tree().physics_frame
	var start_px: Vector2 = vehicle.global_position
	for _step: int in range(180):
		await get_tree().physics_frame
	var weak_push_m: float = Units.px_to_m(vehicle.global_position.distance_to(start_px))
	if weak_push_m > 0.001:
		_fail("Strength 10 pushed the car %.3f m" % weak_push_m)
	actor.data.strength = 30
	for _step: int in range(180):
		await get_tree().physics_frame
	var strong_push_m: float = Units.px_to_m(vehicle.global_position.distance_to(start_px))
	if strong_push_m < 0.2:
		_fail("Strength 30 could not push the car (%.3f m)" % strong_push_m)
	mover.move_vector = Vector2.ZERO
	for _step: int in range(60):
		await get_tree().physics_frame
	var settled_px: Vector2 = vehicle.global_position
	for _step: int in range(60):
		await get_tree().physics_frame
	var coast_m: float = Units.px_to_m(vehicle.global_position.distance_to(settled_px))
	if coast_m > 0.001:
		_fail("pushed car kept sliding %.4f m after the push ended" % coast_m)
	# An occupied vehicle never accepts an external push, even from a strong actor.
	var driver := _make_actor(Vector2(4.0, 280.0))
	if driver == null:
		_fail("could not create the push-test driver")
	else:
		if not vehicle.enter(driver):
			_fail("could not seat the push-test driver")
		elif vehicle.apply_push(actor, Vector2.RIGHT):
			_fail("an occupied vehicle accepted an external push")
		vehicle.exit(driver)
		driver.queue_free()
	actor.queue_free()
	vehicle.queue_free()
	await get_tree().process_frame


func _test_damage() -> void:
	var vehicle := _spawn_vehicle(CAR_PATH, Vector2(80.0, 0.0), 0.0)
	if vehicle == null:
		_fail("could not spawn the damage car")
		return
	var before: float = vehicle.health
	vehicle.damage(50.0, &"test")
	if is_equal_approx(vehicle.health, before):
		_fail("damage() did not reduce health")
	var state: Dictionary = vehicle.get_state()
	if not state.has("health") or not state.has("wheels"):
		_fail("get_state() is missing fields")
	vehicle.global_position = Units.to_px(Vector2(120.0, 0.0))
	vehicle.load_state(state)
	var restored_m: Vector2 = Units.to_m(vehicle.global_position)
	if restored_m.distance_to(Vector2(80.0, 0.0)) > 0.01:
		_fail("load_state() did not restore the position")
	for index: int in range(vehicle.wheels.size()):
		vehicle.set_wheel_present(index, false)
	if vehicle.get_wheel_drive_factor() > 0.0:
		_fail("missing tires still provide traction")
	vehicle.queue_free()


func _spawn_vehicle(data_path: String, position_m: Vector2, heading_rad: float) -> Vehicle:
	var data := load(data_path) as VehicleData
	if data == null:
		return null
	var vehicle := VEHICLE_SCENE.instantiate() as Vehicle
	if vehicle == null:
		return null
	vehicle.data = data
	vehicle.position = Units.to_px(position_m)
	vehicle.rotation = heading_rad
	add_child(vehicle)
	return vehicle


func _make_actor(position_m: Vector2) -> Entity:
	var entity_data := EntityData.new()
	entity_data.full_name = "Test Driver"
	var actor := ENTITY_SCENE.instantiate() as Entity
	if actor == null:
		return null
	actor.data = entity_data
	actor.position = Units.to_px(position_m)
	add_child(actor)
	return actor


func _spawn_wall(position_m: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	wall.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(Units.m_to_px(1.0), Units.m_to_px(20.0))
	shape_node.shape = shape
	wall.add_child(shape_node)
	wall.position = Units.to_px(position_m)
	add_child(wall)
	return wall


func _fail(text: String) -> void:
	_failures.append(text)
