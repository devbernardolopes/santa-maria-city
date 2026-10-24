extends Node2D
## Headless entity animation test: resources, state machine, visual wiring, and fallback.

const ENTITY_SCENE: PackedScene = preload("res://scenes/entities/entity.tscn")
const ANIMATION_SET_PATH: String = "res://resources/entities/entity_00001.tres"
const FRAME_WIDTH_PX: float = 80.0
const SPRITE_WIDTH_M: float = 0.8

var _failures: PackedStringArray = PackedStringArray()


class TestController:
	extends EntityController

	var move_vector: Vector2 = Vector2.ZERO
	var run: bool = false

	func get_move_vector() -> Vector2:
		return move_vector

	func get_move_intent() -> Vector2:
		return move_vector

	func wants_run() -> bool:
		return run


func _ready() -> void:
	await _run()
	if _failures.is_empty():
		print("ANIMATION SMOKE OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("ANIMATION SMOKE FAIL: %s" % failure)
	get_tree().quit(1)


func _run() -> void:
	var animation_set: EntityAnimationSet = _test_animation_set()
	_test_fallbacks(animation_set)
	_test_animator()
	await _test_placeholder()
	await _test_entity_states(animation_set)


func _test_animation_set() -> EntityAnimationSet:
	var animation_set: EntityAnimationSet = load(ANIMATION_SET_PATH) as EntityAnimationSet
	if animation_set == null:
		_fail("animation set did not load")
		return null
	if not animation_set.is_playable():
		_fail("animation set has no playable SpriteFrames")
	if animation_set.states.size() != 3:
		_fail("expected 3 states, got %d" % animation_set.states.size())
	_check_clip(animation_set, EntityAnimationState.State.IDLE, &"idle")
	_check_clip(animation_set, EntityAnimationState.State.WALK, &"walk")
	_check_clip(animation_set, EntityAnimationState.State.RUN, &"run")
	var frames: SpriteFrames = animation_set.sprite_frames
	if frames != null:
		if frames.get_frame_count(&"walk") != 6:
			_fail("walk clip should have 6 frames")
		if frames.get_frame_count(&"run") != 6:
			_fail("run clip should have 6 frames")
		if frames.get_frame_count(&"idle") != 1:
			_fail("idle clip should reuse a single frame")
	var expected_scale: float = Units.m_to_px(SPRITE_WIDTH_M) / FRAME_WIDTH_PX
	if not is_equal_approx(animation_set.get_sprite_scale(), expected_scale):
		_fail("sprite scale %f != %f" % [animation_set.get_sprite_scale(), expected_scale])
	if not is_equal_approx(animation_set.get_frame_width_px(), FRAME_WIDTH_PX):
		_fail("frame width %f != %f" % [animation_set.get_frame_width_px(), FRAME_WIDTH_PX])
	return animation_set


func _test_fallbacks(animation_set: EntityAnimationSet) -> void:
	if animation_set == null:
		return
	var fallback := EntityAnimationSet.new()
	fallback.sprite_frames = animation_set.sprite_frames
	var idle := EntityAnimationState.new()
	idle.state = EntityAnimationState.State.IDLE
	idle.clip = &"idle"
	var walk := EntityAnimationState.new()
	walk.state = EntityAnimationState.State.WALK
	walk.clip = &"walk"
	fallback.states = [idle, walk] as Array[EntityAnimationState]
	if fallback.get_clip(EntityAnimationState.State.RUN) != &"walk":
		_fail("run should fall back to the walk clip")
	var broken := EntityAnimationSet.new()
	var bad := EntityAnimationState.new()
	bad.state = EntityAnimationState.State.IDLE
	bad.clip = &"missing_clip"
	broken.states = [bad] as Array[EntityAnimationState]
	if broken.is_playable():
		_fail("a set without SpriteFrames should not be playable")
	if broken.get_clip(EntityAnimationState.State.IDLE) != &"":
		_fail("a missing clip should resolve to an empty name")


func _test_animator() -> void:
	var animator := EntityAnimator.new()
	_check_state(animator, 0.0, false, false, EntityAnimationState.State.IDLE)
	_check_state(animator, 0.05, false, false, EntityAnimationState.State.IDLE)
	_check_state(animator, 1.0, false, false, EntityAnimationState.State.WALK)
	_check_state(animator, 4.0, true, false, EntityAnimationState.State.RUN)
	_check_state(animator, 4.0, true, true, EntityAnimationState.State.IDLE)


func _check_state(
	animator: EntityAnimator,
	speed_mps: float,
	wants_run: bool,
	seated: bool,
	expected: EntityAnimationState.State
) -> void:
	var state: EntityAnimationState.State = animator.resolve(speed_mps, wants_run, seated)
	if state != expected:
		_fail("animator state %d != %d at %.2f m/s" % [state, expected, speed_mps])


func _test_placeholder() -> void:
	var entity: Entity = _spawn_entity(null)
	await _settle()
	var visual: EntityVisual = entity.get_node("Visual") as EntityVisual
	if visual == null:
		_fail("entity has no EntityVisual")
		entity.queue_free()
		return
	if visual.get_current_clip() != &"":
		_fail("an entity without art should not play a clip")
	if visual.get_node_or_null("Sprite") != null:
		_fail("an entity without art should not create a sprite")
	entity.queue_free()
	await _settle()


func _test_entity_states(animation_set: EntityAnimationSet) -> void:
	var entity: Entity = _spawn_entity(animation_set)
	var visual: EntityVisual = entity.get_node("Visual") as EntityVisual
	var controller := entity.controller as TestController
	if visual == null or controller == null:
		_fail("test entity is missing its visual or controller")
		entity.queue_free()
		return
	await _settle()
	if visual.get_current_clip() != &"idle":
		_fail("a standing entity should play idle, got '%s'" % visual.get_current_clip())
	var sprite := visual.get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite == null:
		_fail("an entity with art should create a sprite")
	else:
		if not is_equal_approx(sprite.rotation, deg_to_rad(90.0)):
			_fail("north-facing art should sit at +90 degrees")
		var expected_scale: float = animation_set.get_sprite_scale()
		if not is_equal_approx(sprite.scale.x, expected_scale):
			_fail("sprite scale %f != %f" % [sprite.scale.x, expected_scale])
	controller.move_vector = Vector2.RIGHT
	await _settle(14)
	if visual.get_current_state() != EntityAnimationState.State.WALK:
		_fail("walking should resolve to WALK")
	if visual.get_current_clip() != &"walk":
		_fail("walking should play the walk clip, got '%s'" % visual.get_current_clip())
	if absf(angle_difference(visual.rotation, entity.facing.angle())) > 0.2:
		_fail(
			"visual rotation %f should track heading %f" % [visual.rotation, entity.facing.angle()]
		)
	controller.run = true
	await _settle()
	if visual.get_current_clip() != &"run":
		_fail("running should play the run clip, got '%s'" % visual.get_current_clip())
	controller.run = false
	controller.move_vector = Vector2.ZERO
	await _settle()
	if visual.get_current_clip() != &"idle":
		_fail("stopping should return to idle, got '%s'" % visual.get_current_clip())
	entity.queue_free()
	await _settle()


func _spawn_entity(animation_set: EntityAnimationSet) -> Entity:
	var entity: Entity = ENTITY_SCENE.instantiate() as Entity
	var data := EntityData.new()
	data.id = &"anim_test"
	data.full_name = "Animation Test"
	data.walk_speed_mps = 1.5
	data.run_speed_mps = 5.0
	data.animation_set = animation_set
	entity.data = data
	entity.set_controller(TestController.new())
	entity.position = Vector2.ZERO
	add_child(entity)
	return entity


## Lets physics and idle frames run so the visual samples the body.
func _settle(steps: int = 4) -> void:
	for _step: int in range(steps):
		await get_tree().physics_frame
		await get_tree().process_frame


func _check_clip(
	animation_set: EntityAnimationSet, state: EntityAnimationState.State, expected: StringName
) -> void:
	var clip: StringName = animation_set.get_clip(state)
	if clip != expected:
		_fail("clip for state %d is '%s', expected '%s'" % [state, clip, expected])


func _fail(message: String) -> void:
	_failures.append(message)
