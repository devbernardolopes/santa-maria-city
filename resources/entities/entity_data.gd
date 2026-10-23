class_name EntityData
extends Resource
## Persistent identity, ability scores, and preferences for one entity.

enum Sex { MALE, FEMALE }
enum Ability { STRENGTH, DEXTERITY, CONSTITUTION, INTELLIGENCE, WISDOM, CHARISMA }

const MALE_FIRST_NAMES: Array[String] = [
	"João",
	"Pedro",
	"Lucas",
	"Gabriel",
	"Rafael",
	"Bruno",
	"Carlos",
	"Eduardo",
]
const FEMALE_FIRST_NAMES: Array[String] = [
	"Maria",
	"Ana",
	"Júlia",
	"Beatriz",
	"Camila",
	"Fernanda",
	"Larissa",
	"Patrícia",
]
const LAST_NAMES: Array[String] = [
	"Silva",
	"Santos",
	"Oliveira",
	"Souza",
	"Pereira",
	"Costa",
	"Rodrigues",
	"Almeida",
]
const INTEREST_TAGS: Array[StringName] = [
	&"music",
	&"football",
	&"cooking",
	&"reading",
	&"gardening",
	&"travel",
	&"coffee",
	&"fishing",
	&"movies",
	&"walking",
]
const DAYS_IN_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

@export var id: StringName = &""
@export var full_name: String = ""
@export var sex: Sex = Sex.MALE
@export var birth_year: int = 1990
@export var birth_month: int = 1
@export var birth_day: int = 1
@export var likes: Array[StringName] = []
@export var dislikes: Array[StringName] = []
@export_range(1, 30) var strength: int = 10
@export_range(1, 30) var dexterity: int = 10
@export_range(1, 30) var constitution: int = 10
@export_range(1, 30) var intelligence: int = 10
@export_range(1, 30) var wisdom: int = 10
@export_range(1, 30) var charisma: int = 10
@export var walk_speed_mps: float = 1.5
@export var run_speed_mps: float = 5.0

## D&D 5.5e-inspired mass-movement formula.
## Strength modifier = floor((strength - 10) / 2)  +0 at Str 10, +5 at Str 20, +10 at Str 30.
## Maximum mass the entity can push/drag (kg) = 50 + (modifier * 10).
## Str 10 -> 50 kg, Str 15 -> 70 kg, Str 20 -> 100 kg, Str 30 -> 150 kg.
func get_strength_modifier() -> int:
	return floor((float(strength) - 10.0) / 2.0)

func get_max_pushable_mass_kg() -> float:
	var modifier = get_strength_modifier()
	return 50.0 + (modifier * 10.0)


func get_ability(ability: Ability) -> int:
	match ability:
		Ability.STRENGTH:
			return strength
		Ability.DEXTERITY:
			return dexterity
		Ability.CONSTITUTION:
			return constitution
		Ability.INTELLIGENCE:
			return intelligence
		Ability.WISDOM:
			return wisdom
		Ability.CHARISMA:
			return charisma
		_:
			return 10


func get_modifier(ability: Ability) -> int:
	return floori((float(get_ability(ability)) - 10.0) / 2.0)


## Whole years lived on the given date. A Feb 29 birthday counts on Mar 1 in non-leap years.
func get_age_years(year: int, month: int, day: int) -> int:
	var birthday_reached: bool = month > birth_month or (month == birth_month and day >= birth_day)
	var age: int = year - birth_year
	if not birthday_reached:
		age -= 1
	return maxi(0, age)


static func create_random(rng: RandomNumberGenerator) -> EntityData:
	var data := EntityData.new()
	data.sex = EntityData.Sex.MALE if rng.randi_range(0, 1) == 0 else EntityData.Sex.FEMALE
	var first_names: Array[String] = (
		MALE_FIRST_NAMES if data.sex == EntityData.Sex.MALE else FEMALE_FIRST_NAMES
	)
	data.full_name = (
		"%s %s"
		% [
			first_names[rng.randi_range(0, first_names.size() - 1)],
			LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)],
		]
	)
	data.birth_year = rng.randi_range(1950, 2008)
	data.birth_month = rng.randi_range(1, 12)
	data.birth_day = rng.randi_range(1, _days_in_month(data.birth_month, data.birth_year))
	data.strength = _roll_ability(rng)
	data.dexterity = _roll_ability(rng)
	data.constitution = _roll_ability(rng)
	data.intelligence = _roll_ability(rng)
	data.wisdom = _roll_ability(rng)
	data.charisma = _roll_ability(rng)
	data.likes = _pick_tags(rng, INTEREST_TAGS, rng.randi_range(0, 3))
	data.dislikes = _pick_tags(rng, INTEREST_TAGS, rng.randi_range(0, 3))
	return data


static func _roll_ability(rng: RandomNumberGenerator) -> int:
	var total: int = 0
	var lowest: int = 7
	for _roll_index: int in range(4):
		var roll: int = rng.randi_range(1, 6)
		total += roll
		lowest = mini(lowest, roll)
	return total - lowest


static func _days_in_month(month: int, year: int) -> int:
	if month == 2 and _is_leap_year(year):
		return 29
	return DAYS_IN_MONTH[clampi(month - 1, 0, DAYS_IN_MONTH.size() - 1)]


static func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func _pick_tags(
	rng: RandomNumberGenerator, source: Array[StringName], count: int
) -> Array[StringName]:
	var pool: Array[StringName] = []
	pool.assign(source)
	var result: Array[StringName] = []
	for _pick_index: int in range(mini(count, pool.size())):
		var index: int = rng.randi_range(0, pool.size() - 1)
		result.append(pool[index])
		pool.remove_at(index)
	return result
