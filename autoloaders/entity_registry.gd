extends Node
## Central store for entity data and relationship edges. No node references.

signal entity_registered(id: StringName)
signal relationship_changed(from_id: StringName, to_id: StringName)

var _data_by_id: Dictionary = {}
var _relationships: Dictionary = {}
var _next_entity_number: int = 1


func register(data: EntityData) -> StringName:
	if data == null:
		push_warning("EntityRegistry: cannot register null EntityData.")
		return &""
	if not data.id.is_empty():
		if _data_by_id.has(data.id):
			if _data_by_id[data.id] != data:
				push_warning(
					(
						"EntityRegistry: id '%s' is already registered; keeping the existing data."
						% data.id
					)
				)
			return data.id
		_data_by_id[data.id] = data
		entity_registered.emit(data.id)
		return data.id
	var assigned_id: StringName = _next_id()
	data.id = assigned_id
	_data_by_id[assigned_id] = data
	entity_registered.emit(assigned_id)
	return assigned_id


func get_data(id: StringName) -> EntityData:
	if id.is_empty():
		return null
	return _data_by_id.get(id) as EntityData


func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_data_by_id.keys())
	return ids


func set_relationship(rel: Relationship) -> void:
	if rel == null:
		return
	_relationships[_relationship_key(rel.from_id, rel.to_id)] = rel
	relationship_changed.emit(rel.from_id, rel.to_id)


func get_relationship(from_id: StringName, to_id: StringName) -> Relationship:
	return _relationships.get(_relationship_key(from_id, to_id)) as Relationship


func get_relationships_of(id: StringName) -> Array[Relationship]:
	var result: Array[Relationship] = []
	for value: Variant in _relationships.values():
		var rel: Relationship = value as Relationship
		if rel != null and (rel.from_id == id or rel.to_id == id):
			result.append(rel)
	return result


func _next_id() -> StringName:
	var candidate: StringName = &""
	while candidate.is_empty():
		var attempt: StringName = StringName("e_%06d" % _next_entity_number)
		_next_entity_number += 1
		if not _data_by_id.has(attempt):
			candidate = attempt
	return candidate


func _relationship_key(from_id: StringName, to_id: StringName) -> StringName:
	return StringName("%s|%s" % [String(from_id), String(to_id)])
