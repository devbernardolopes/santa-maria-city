class_name PushRules
extends RefCounted
## Strength-gated mass rules shared by entities, vehicles, and world objects.
##
## The base rule follows D&D 5.5e (2024): carrying capacity is Strength x 15 lb and
## push/drag/lift is twice that (Strength x 30 lb). This project extends the curve so
## every 5 points of Strength doubles the capacity, which keeps the 10-30 ability
## range useful for tonne-scale vehicles. Nothing caps the score here, so raising the
## ability limit later widens the reachable masses automatically.

const POUNDS_PER_KILOGRAM: float = 2.20462262
## D&D 5.5e push/drag/lift: twice the carrying capacity of Strength x 15 lb.
const PUSH_POUNDS_PER_STRENGTH: float = 30.0
const CARRY_POUNDS_PER_STRENGTH: float = 15.0
## Capacity doubles every 5 points of Strength (house extension of the D&D curve).
const DOUBLING_STRENGTH_STEP: float = 5.0
## External push speed range, in m/s. Pushing is deliberately slower than walking.
const MIN_PUSH_SPEED_MPS: float = 0.15
const MAX_PUSH_SPEED_MPS: float = 0.8
const CAPACITY_EPSILON_KG: float = 0.0001


## Raw D&D 5.5e push/drag/lift capacity at this Strength, in kilograms.
static func dnd_push_capacity_kg(strength: int) -> float:
	return maxf(0.0, float(strength)) * PUSH_POUNDS_PER_STRENGTH / POUNDS_PER_KILOGRAM


## Weight the entity can carry without penalties, in kilograms (Strength x 15 lb).
static func carry_capacity_kg(strength: int) -> float:
	return maxf(0.0, float(strength)) * CARRY_POUNDS_PER_STRENGTH / POUNDS_PER_KILOGRAM


## Push/drag/lift capacity in kilograms; doubles every 5 Strength points from the
## D&D baseline at Strength 10 (about 136 kg).
static func push_capacity_kg(strength: int) -> float:
	return (
		dnd_push_capacity_kg(10)
		* pow(2.0, (float(strength) - 10.0) / DOUBLING_STRENGTH_STEP)
	)


## Effective load of an object: its mass scaled by the authored push resistance.
static func push_load_kg(mass_kg: float, push_resistance: float) -> float:
	return maxf(0.0, mass_kg) * maxf(0.0, push_resistance)


static func can_push(strength: int, load_kg: float) -> bool:
	return load_kg <= 0.0 or push_capacity_kg(strength) + CAPACITY_EPSILON_KG >= load_kg


## Lowest ability score whose capacity covers the load; 0 for a weightless object.
## Returns values above 30 when the load is beyond the current ability range, so the
## caller can report the real requirement instead of hiding it behind a cap.
static func min_strength_for(load_kg: float) -> int:
	if load_kg <= 0.0:
		return 0
	var base: float = dnd_push_capacity_kg(10)
	var steps: float = log(load_kg / base) / log(2.0)
	return maxi(1, ceili(10.0 + DOUBLING_STRENGTH_STEP * steps - CAPACITY_EPSILON_KG))


## Speed at which an entity moves a load: slow at the threshold, faster with a large
## surplus, never above MAX_PUSH_SPEED_MPS.
static func push_speed_mps(strength: int, load_kg: float) -> float:
	if load_kg <= 0.0:
		return MAX_PUSH_SPEED_MPS
	var capacity: float = push_capacity_kg(strength)
	if capacity + CAPACITY_EPSILON_KG < load_kg:
		return 0.0
	var surplus: float = clampf((capacity - load_kg) / load_kg, 0.0, 1.0)
	return lerpf(MIN_PUSH_SPEED_MPS, MAX_PUSH_SPEED_MPS, surplus)
