class_name VegetationBatch
extends Node2D
## Draws one chunk's vegetation in a single canvas item; runtime only.

enum Mode { GROUND, CANOPY }

const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.18)
const SHADOW_OFFSET_M: Vector2 = Vector2(0.18, 0.28)
const SHADOW_RADIUS_SCALE: float = 0.9
const SHADOW_HEIGHT_SCALE: float = 0.55

var _data: VegetationChunkData = null
var _rules: VegetationRules = null
var _origin_m: Vector2 = Vector2.ZERO
var _mode: Mode = Mode.GROUND


func configure(
	data: VegetationChunkData,
	rules: VegetationRules,
	origin_m: Vector2,
	mode: Mode
) -> void:
	_data = data
	_rules = rules
	_origin_m = origin_m
	_mode = mode
	y_sort_enabled = false
	queue_redraw()


func _draw() -> void:
	if _data == null or _rules == null or _rules.species.is_empty():
		return
	for index: int in range(_data.count()):
		var species_index: int = _data.species_index[index]
		if species_index < 0 or species_index >= _rules.species.size():
			continue
		var species: VegetationSpecies = _rules.species[species_index]
		if species == null:
			continue
		if _mode == Mode.CANOPY:
			if species.kind == VegetationSpecies.Kind.TREE:
				_draw_canopy(species, index)
		else:
			_draw_ground(species, index)


func _draw_ground(species: VegetationSpecies, index: int) -> void:
	var position: Vector2 = Units.to_px(_data.positions_m[index] - _origin_m)
	var radius: float = Units.m_to_px(_data.radii_m[index])
	var rotation: float = _data.rotations[index]
	_draw_shadow(position, radius)
	match species.kind:
		VegetationSpecies.Kind.TREE:
			var trunk_radius: float = maxf(Units.m_to_px(species.trunk_radius_m), 1.0)
			if species.ground_texture != null:
				_draw_textured(
					species.ground_texture,
					position,
					trunk_radius * 2.0,
					rotation,
					species.ground_color
				)
			else:
				draw_circle(position, trunk_radius, species.ground_color)
		VegetationSpecies.Kind.BUSH:
			if species.ground_texture != null:
				_draw_textured(
					species.ground_texture,
					position,
					radius * 2.0,
					rotation,
					species.ground_color
				)
			else:
				draw_circle(position, radius, species.ground_color)
				draw_circle(
					position + Vector2(-radius * 0.18, -radius * 0.18),
					radius * 0.55,
					species.ground_color.lightened(0.12)
				)
		VegetationSpecies.Kind.ROCK:
			if species.ground_texture != null:
				_draw_textured(
					species.ground_texture,
					position,
					radius * 2.0,
					rotation,
					species.ground_color
				)
			else:
				_draw_rock(position, radius, rotation, species.ground_color)


func _draw_canopy(species: VegetationSpecies, index: int) -> void:
	var position: Vector2 = Units.to_px(_data.positions_m[index] - _origin_m)
	var radius: float = Units.m_to_px(_data.radii_m[index])
	var rotation: float = _data.rotations[index]
	var canopy_color: Color = _with_alpha(species.canopy_color, species.canopy_alpha)
	if species.canopy_texture != null:
		_draw_textured(
			species.canopy_texture,
			position,
			radius * 2.0,
			rotation,
			canopy_color
		)
		return
	draw_circle(position, radius, canopy_color)
	draw_circle(
		position + Vector2(-radius * 0.22, -radius * 0.22),
		radius * 0.55,
		_with_alpha(species.canopy_color.lightened(0.12), species.canopy_alpha * 0.7)
	)


func _draw_shadow(position: Vector2, radius: float) -> void:
	var center: Vector2 = position + Units.to_px(SHADOW_OFFSET_M)
	var shadow_radius: float = maxf(radius * SHADOW_RADIUS_SCALE, 1.0)
	var points: PackedVector2Array = _ellipse(
		center,
		shadow_radius,
		shadow_radius * SHADOW_HEIGHT_SCALE,
		16
	)
	draw_colored_polygon(points, SHADOW_COLOR)


func _draw_rock(position: Vector2, radius: float, rotation: float, color: Color) -> void:
	var points := PackedVector2Array()
	var sides: int = 7
	for index: int in range(sides):
		var angle: float = rotation + TAU * float(index) / float(sides)
		var wobble: float = 0.82 + 0.12 * sin(float(index) * 12.9898 + rotation * 78.233)
		points.append(position + Vector2(cos(angle), sin(angle)) * radius * wobble)
	draw_colored_polygon(points, color)
	var outline := points
	outline.append(points[0])
	draw_polyline(outline, color.darkened(0.25), 1.0)


func _draw_textured(
	texture: Texture2D,
	position: Vector2,
	diameter: float,
	rotation: float,
	tint: Color
) -> void:
	if texture == null:
		return
	var half: float = maxf(diameter * 0.5, 0.5)
	draw_set_transform(position, rotation, Vector2.ONE)
	draw_texture_rect(
		texture,
		Rect2(-Vector2(half, half), Vector2(diameter, diameter)),
		false,
		tint
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ellipse(center: Vector2, radius_x: float, radius_y: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in range(maxi(segments, 3)):
		var angle: float = TAU * float(index) / float(maxi(segments, 3))
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points


func _with_alpha(color: Color, alpha: float) -> Color:
	var result: Color = color
	result.a = alpha
	return result
