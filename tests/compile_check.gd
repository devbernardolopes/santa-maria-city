extends Node
## Headless compile check: loads every game script with autoloads available.

const ROOTS: Array[String] = [
	"res://autoloaders",
	"res://resources",
	"res://scenes",
	"res://scripts",
	"res://tests",
]

var _checked: int = 0
var _failed: PackedStringArray = PackedStringArray()


func _ready() -> void:
	for root: String in ROOTS:
		_scan(root)
	if _failed.is_empty():
		print("COMPILE CHECK OK: %d scripts" % _checked)
		get_tree().quit(0)
		return
	for path: String in _failed:
		print("COMPILE CHECK FAIL: %s" % path)
	print("COMPILE CHECK FAILED: %d of %d scripts" % [_failed.size(), _checked])
	get_tree().quit(1)


func _scan(directory: String) -> void:
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var path: String = directory.path_join(entry)
		if dir.current_is_dir():
			_scan(path)
		elif entry.ends_with(".gd"):
			_check(path)
		entry = dir.get_next()
	dir.list_dir_end()


func _check(path: String) -> void:
	_checked += 1
	var script: Script = load(path) as Script
	if script == null:
		_failed.append(path)
		return
	if not script.can_instantiate():
		_failed.append(path)
