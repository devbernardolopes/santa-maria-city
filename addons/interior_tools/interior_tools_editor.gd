# Interior Tools Editor Plugin
# Provides visual object placement in building interiors

extends EditorPlugin

# --- Dock Window (simplified) ---

dock_content = null

func _enter_tree() -> void:
 # The editor will manage the dock; we just need to register
 # In Godot 4, EditorPlugin handles dock windows automatically
 # when they're added via EditorInterface

func _exit_tree() -> void:
 if dock_content != null:
  dock_content.queue_free()
 dock_content = null

# --- Object Data Browser ---

## Get all ObjectData resources in the project
func get_all_object_data() -> Array:
 var resources := []
 var path := "res://resources/objects"
 var dir := DirAccess.open_path(path)
 if dir == null:
  return resources
 var files := dir.get_dir_list()
 for f in files:
  if f.ends_with(".tres"):
   var full_path := "res://resources/objects/" + f
   var res := load(full_path)
   if res is ObjectData:
    resources.append(res)
 return resources

func filter_by_kind(resources: Array, kind: String) -> Array:
 var filtered := []
 for r in resources:
  if r.kind == kind or kind == "":
   filtered.append(r)
 return filtered

## Resource IDs for dropdown
func get_resource_ids(resources: Array) -> Array:
 var ids := []
 for r in resources:
  ids.append(r.id)
 return ids

# --- Placement Helpers ---

func place_object_at(data: ObjectData, position_m: Vector2) -> WorldObject:
 if data == null:
  push_error("Interior Tools: Null ObjectData")
  return null
 var instance := WorldObject.new_from_data(data)
 # Convert meters to pixels (Units.PX_PER_METER = 16)
 instance.global_position = position_m * 16.0
 return instance

## Get building footprint in meters for snapping
func get_building_footprint_m(osm_id: String) -> PackedVector2Array:
 var world := get_node_or_null("/root/World") as Node2D
 if world == null:
  return PackedVector2Array()
 var map_node := world.get_node_or_null("Map") as MapLoader
 if map_node == null:
  return PackedVector2Array()
 return map_node.get_building_ring_m(osm_id)

# --- Menu Integration ---

func _add_tools_menu() -> void:
 # In Godot 4, we can use EditorInterface to add menu items
 # This is a placeholder; actual menu integration depends on editor version
 pass

# --- Status Messages ---

func push_success(text: String) -> void:
 print("[Interior Tools] SUCCESS: " + text)

func push_error(text: String) -> void:
 print("[Interior Tools] ERROR: " + text)

func push_warning(text: String) -> void:
 print("[Interior Tools] WARNING: " + text)