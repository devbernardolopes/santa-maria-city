class_name EntityVisual
extends Node2D
## Placeholder body: a filled circle plus a triangle showing the facing direction.

const BODY_RADIUS_M: float = 0.35
const FACING_LENGTH_M: float = 0.22
const FACING_HALF_WIDTH_M: float = 0.09

@export var body_color: Color = Color("d9822b"):
	set(value):
		body_color = value
		queue_redraw()


func _draw() -> void:
	var radius: float = Units.m_to_px(BODY_RADIUS_M)
	if radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, radius, body_color)
	draw_arc(
		Vector2.ZERO,
		radius,
		0.0,
		TAU,
		32,
		body_color.darkened(0.35),
		maxf(1.0, radius * 0.12),
		true
	)
	var tip := Vector2(radius + Units.m_to_px(FACING_LENGTH_M), 0.0)
	var half_width: float = Units.m_to_px(FACING_HALF_WIDTH_M)
	var base_x: float = radius * 0.55
	var triangle := PackedVector2Array(
		[
			tip,
			Vector2(base_x, -half_width),
			Vector2(base_x, half_width),
		]
	)
	draw_colored_polygon(triangle, body_color.lightened(0.18))
