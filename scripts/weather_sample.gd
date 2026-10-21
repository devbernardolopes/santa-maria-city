class_name WeatherSample
extends RefCounted
## One weather reading computed from the seed and time; written once, then shared.

enum Condition { CLEAR, CLOUDY, RAIN }

var condition: Condition = Condition.CLEAR
var temperature_c: float = 0.0
var cloud_cover: float = 0.0
var rain_intensity: float = 0.0


func is_raining() -> bool:
	return condition == Condition.RAIN
