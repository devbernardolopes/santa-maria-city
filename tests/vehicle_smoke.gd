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
	_test_world_scene()
	await _test_spawner()
	await _test_drive_and_impact()
	await _test_blocked_vehicle()
	await _test_enter_exit()
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
		'{"version":1,"vehicles":[{"id":"v_test",'
		+ '"data":"res://resources/vehicles/taxi.tres",'
		+ '"position":[200.0,0.0],"heading_deg":90}]}'
	)
	file.close()
	var spawned: Array[Vehicle] = []
	spawner.vehicle_spawned.connect(
		func(vehicle: Vehicle) -> void: spawned.append(vehicle)
	)
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
		"VEHICLE SMOKE blocked speed: %.3f m/s, health %.1f -> %.1f"
		% [blocked_speed, health_before, health_after]
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
