extends Node2D
## Headless entrance test: schedules, lock matching, transform helpers, prompts, and art.

const ENTRANCE_SCENE: PackedScene = preload("res://scenes/objects/entrance.tscn")
const FRAME_WIDTH_PX: float = 16.0

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	await _run()
	if _failures.is_empty():
		print("ENTRANCE SMOKE OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("ENTRANCE SMOKE FAIL: %s" % failure)
	get_tree().quit(1)


func _run() -> void:
	_test_plain_schedule()
	_test_wrapped_schedule()
	_test_prompts()
	_test_locks()
	_test_transform()
	await _test_scene_entrance()


func _test_plain_schedule() -> void:
	var entry: EntranceScheduleEntry = _entry_on(0, 8.0, 18.0)
	var entries: Array[EntranceScheduleEntry] = [entry]
	_check("monday 08:00 is open", EntranceSchedule.is_open(entries, 0, 8.0))
	_check("monday 17:59 is open", EntranceSchedule.is_open(entries, 0, 17.99))
	_check("monday 18:00 is closed", not EntranceSchedule.is_open(entries, 0, 18.0))
	_check("saturday is closed", not EntranceSchedule.is_open(entries, 5, 12.0))
	var empty: Array[EntranceScheduleEntry] = []
	_check("an empty schedule is always open", EntranceSchedule.is_open(empty, 3, 3.0))
	_check("next opening monday 07:00 is 08:00", EntranceSchedule.next_opening_text(entries, 0, 7.0) == "08:00")
	_check(
		"next opening sunday noon is monday 08:00",
		EntranceSchedule.next_opening_text(entries, 6, 12.0) == "08:00"
	)


func _test_wrapped_schedule() -> void:
	var entry: EntranceScheduleEntry = _entry_on(4, 22.0, 2.0)
	var entries: Array[EntranceScheduleEntry] = [entry]
	_check("friday 23:00 is open", EntranceSchedule.is_open(entries, 4, 23.0))
	_check("saturday 01:00 is open", EntranceSchedule.is_open(entries, 5, 1.0))
	_check("saturday 03:00 is closed", not EntranceSchedule.is_open(entries, 5, 3.0))
	_check("friday 12:00 is closed", not EntranceSchedule.is_open(entries, 4, 12.0))


func _test_prompts() -> void:
	var entrance: Entrance = ENTRANCE_SCENE.instantiate() as Entrance
	_check("an unlabeled door prompts Enter", entrance.get_prompt_text() == "Enter")
	entrance.label = "Bakery"
	_check("a labeled door prompts Enter Bakery", entrance.get_prompt_text() == "Enter Bakery")
	var open_result: Dictionary = entrance.evaluate(0, 12.0)
	_check("an open door is available", bool(open_result["available"]))
	_check("an open door prompts Enter Bakery", String(open_result["prompt"]) == "Enter Bakery")
	var entry: EntranceScheduleEntry = _entry_on(0, 8.0, 18.0)
	entrance.schedule.append(entry)
	var closed_result: Dictionary = entrance.evaluate(0, 19.0)
	_check("a closed door is unavailable", not bool(closed_result["available"]))
	_check(
		"a closed door shows the next opening",
		String(closed_result["prompt"]).begins_with("Closed · opens ")
	)
	entrance.locked = true
	var locked_result: Dictionary = entrance.evaluate(0, 12.0)
	_check("a locked door hides its opening hours", String(locked_result["prompt"]) == "Locked")
	entrance.free()


func _test_locks() -> void:
	var entrance: Entrance = ENTRANCE_SCENE.instantiate() as Entrance
	for index: int in range(3):
		var lock := EntranceLock.new()
		lock.name = "lock_%d" % index
		entrance.locks.append(lock)
	entrance.locks[0].required_key_item_id = &"brass_key"
	entrance.locks[1].required_key_item_id = &"brass_key"
	entrance.locks[2].required_key_item_id = &"iron_key"
	_check("three locks are authored", entrance.get_total_locks() == 3)
	_check("the brass key opens two locks", entrance.get_matching_locks(&"brass_key").size() == 2)
	_check("the iron key opens one lock", entrance.get_matching_locks(&"iron_key").size() == 1)
	_check("an unknown key opens no lock", entrance.get_matching_locks(&"gold_key").is_empty())
	_check("an empty key opens no lock", entrance.get_matching_locks(&"").is_empty())
	entrance.free()


func _test_transform() -> void:
	var entrance: Entrance = ENTRANCE_SCENE.instantiate() as Entrance
	entrance.position = Units.to_px(Vector2(10.0, 20.0))
	entrance.rotation = PI * 0.5
	_check("position round-trips through meters", entrance.get_position_m().is_equal_approx(Vector2(10.0, 20.0)))
	_check(
		"the outward normal follows rotation",
		entrance.get_outward_normal().is_equal_approx(Vector2.DOWN)
	)
	entrance.name = "BakeryDoor"
	_check("the save key falls back to the node name", entrance.get_save_key() == "BakeryDoor")
	entrance.id = "way/123#0"
	_check("the save key uses the authored id", entrance.get_save_key() == "way/123#0")
	entrance.free()


func _test_scene_entrance() -> void:
	var entrance: Entrance = ENTRANCE_SCENE.instantiate() as Entrance
	entrance.label = "Shop"
	entrance.schedule.append(_entry_on(0, 9.0, 17.0))
	add_child(entrance)
	await get_tree().process_frame
	entrance.refresh_availability(0, 12.0)
	var interactable: Interactable = entrance.get_node_or_null("Interactable") as Interactable
	_check("the entrance is available during opening hours", entrance.is_available())
	_check("the interactable prompt is live", interactable != null and interactable.get_prompt() == "Enter Shop")
	entrance.refresh_availability(0, 20.0)
	_check("the entrance is unavailable after closing", not entrance.is_available())
	_check(
		"the interactable shows the closed prompt",
		interactable != null and interactable.get_prompt().begins_with("Closed · opens ")
	)
	entrance.locked = true
	entrance.refresh_availability(0, 12.0)
	_check(
		"the interactable shows the locked prompt",
		interactable != null and interactable.get_prompt() == "Locked"
	)
	entrance.locked = false
	_check("a door without art uses the placeholder", entrance.is_using_placeholder())
	_check("a door without art creates no sprite", entrance.get_node_or_null("Sprite") == null)
	entrance.sprite_frames = _build_frames()
	entrance.refresh_availability(0, 12.0)
	_check("art replaces the placeholder", not entrance.is_using_placeholder())
	_check("the open clip plays while available", entrance.get_current_clip() == &"open")
	var sprite: AnimatedSprite2D = entrance.get_node_or_null("Sprite") as AnimatedSprite2D
	_check("art creates an animated sprite", sprite != null)
	if sprite != null:
		_check("north-facing art sits at +90 degrees", is_equal_approx(sprite.rotation, deg_to_rad(90.0)))
		var expected_scale: float = Units.m_to_px(entrance.sprite_width_m) / FRAME_WIDTH_PX
		_check("sprite scale follows the authored width", is_equal_approx(sprite.scale.x, expected_scale))
	entrance.refresh_availability(0, 20.0)
	_check("the closed clip plays while unavailable", entrance.get_current_clip() == &"closed")
	entrance.queue_free()
	await get_tree().process_frame


## A one-day interval starting on `day` (0 = Monday).
func _entry_on(day: int, from_hour: float, to_hour: float) -> EntranceScheduleEntry:
	var entry := EntranceScheduleEntry.new()
	entry.monday = day == 0
	entry.tuesday = day == 1
	entry.wednesday = day == 2
	entry.thursday = day == 3
	entry.friday = day == 4
	entry.saturday = day == 5
	entry.sunday = day == 6
	entry.from_hour = from_hour
	entry.to_hour = to_hour
	return entry


func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var image: Image = Image.create_empty(int(FRAME_WIDTH_PX), 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture: Texture2D = ImageTexture.create_from_image(image)
	for clip: StringName in [&"open", &"closed"]:
		frames.add_animation(clip)
		frames.add_frame(clip, texture)
	return frames


func _check(description: String, condition: bool) -> void:
	if not condition:
		_failures.append(description)
