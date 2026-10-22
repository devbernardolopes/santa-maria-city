class_name Units
extends RefCounted
## Single source of truth for meter/pixel conversion.

const PX_PER_METER: float = 16.0


static func m_to_px(meters: float) -> float:
	return meters * PX_PER_METER


static func px_to_m(pixels: float) -> float:
	return pixels / PX_PER_METER


static func to_px(point_m: Vector2) -> Vector2:
	return point_m * PX_PER_METER


static func to_m(point_px: Vector2) -> Vector2:
	return point_px / PX_PER_METER
