class_name VegetationRules
extends Resource
## Species table, terrain rules, and street-tree rules for procedural vegetation.

static var _shared: VegetationRules = null

@export var species: Array[VegetationSpecies] = []
@export var rules: Array[VegetationRule] = []
@export var street_rules: Array[StreetTreeRule] = []


func find_species(id: StringName) -> VegetationSpecies:
	for entry: VegetationSpecies in species:
		if entry != null and entry.id == id:
			return entry
	return null


## Exact category + kind + surface first, then category + kind with an empty surface.
func find_rule(sample: TerrainSample) -> VegetationRule:
	if sample == null:
		return null
	for rule: VegetationRule in rules:
		if rule == null:
			continue
		if rule.category != sample.category or rule.kind != sample.kind:
			continue
		if rule.surface.is_empty() or rule.surface != sample.surface:
			continue
		return rule
	for rule: VegetationRule in rules:
		if rule == null:
			continue
		if (
			rule.category == sample.category
			and rule.kind == sample.kind
			and rule.surface.is_empty()
		):
			return rule
	return null


func find_street_rule(road_kind: StringName) -> StreetTreeRule:
	for rule: StreetTreeRule in street_rules:
		if rule != null and rule.road_kind == road_kind:
			return rule
	return null


static func create_default() -> VegetationRules:
	var result := VegetationRules.new()
	(
		result
		. species
		. assign(
			[
				_make_species(
					&"ipe",
					"Ipê",
					"A tall Brazilian hardwood with dense green foliage.",
					VegetationSpecies.Kind.TREE,
					0.30,
					3.0,
					4.5,
					true,
					0.8,
					Color(0.38, 0.28, 0.18, 1.0),
					Color(0.30, 0.52, 0.22, 1.0),
					0.82,
					_make_properties(
						900.0,
						false,
						0.8,
						true,
						320.0,
						1_000_000.0,
						16_000_000.0,
						true,
						25_000.0,
						40_000.0,
						100.0
					)
				),
				_make_species(
					&"jacaranda",
					"Jacarandá",
					"A broad tree known for its purple blossoms.",
					VegetationSpecies.Kind.TREE,
					0.32,
					3.5,
					5.0,
					true,
					0.8,
					Color(0.36, 0.27, 0.19, 1.0),
					Color(0.48, 0.40, 0.63, 1.0),
					0.82,
					_make_properties(
						1000.0,
						false,
						0.75,
						true,
						310.0,
						1_100_000.0,
						15_000_000.0,
						true,
						24_000.0,
						38_000.0,
						90.0
					)
				),
				_make_species(
					&"eucalyptus",
					"Eucalyptus",
					"A fast-growing tree with narrow, pale leaves.",
					VegetationSpecies.Kind.TREE,
					0.28,
					2.5,
					4.0,
					true,
					0.8,
					Color(0.40, 0.33, 0.25, 1.0),
					Color(0.27, 0.46, 0.30, 1.0),
					0.82,
					_make_properties(
						1200.0,
						false,
						0.7,
						true,
						280.0,
						1_300_000.0,
						18_000_000.0,
						true,
						30_000.0,
						45_000.0,
						120.0
					)
				),
				_make_species(
					&"araucaria",
					"Araucária",
					"A tall southern Brazilian conifer with a layered crown.",
					VegetationSpecies.Kind.TREE,
					0.35,
					2.5,
					3.5,
					true,
					0.8,
					Color(0.34, 0.25, 0.17, 1.0),
					Color(0.20, 0.38, 0.22, 1.0),
					0.82,
					_make_properties(
						1100.0,
						false,
						0.8,
						true,
						330.0,
						1_200_000.0,
						17_000_000.0,
						true,
						28_000.0,
						42_000.0,
						200.0
					)
				),
				_make_species(
					&"hibiscus",
					"Hibiscus",
					"A flowering shrub with glossy leaves.",
					VegetationSpecies.Kind.BUSH,
					0.0,
					0.5,
					0.9,
					false,
					0.4,
					Color(0.25, 0.50, 0.22, 1.0),
					Color(0.25, 0.50, 0.22, 1.0),
					0.9,
					_make_properties(
						20.0, true, 0.7, true, 260.0, 150_000.0, 12_000_000.0, false, 0.0, 0.0, 20.0
					)
				),
				_make_species(
					&"azalea",
					"Azalea",
					"A low ornamental shrub.",
					VegetationSpecies.Kind.BUSH,
					0.0,
					0.4,
					0.8,
					false,
					0.4,
					Color(0.28, 0.46, 0.24, 1.0),
					Color(0.28, 0.46, 0.24, 1.0),
					0.9,
					_make_properties(
						12.0, true, 0.7, true, 250.0, 120_000.0, 11_000_000.0, false, 0.0, 0.0, 15.0
					)
				),
				_make_species(
					&"rock",
					"Rock",
					"A loose stone that can be moved with enough force.",
					VegetationSpecies.Kind.ROCK,
					0.0,
					0.4,
					0.8,
					true,
					0.5,
					Color(0.46, 0.46, 0.44, 1.0),
					Color(0.46, 0.46, 0.44, 1.0),
					1.0,
					_make_properties(
						400.0, true, 0.9, false, 0.0, 0.0, 0.0, true, 80_000.0, 20_000.0, 0.0
					)
				),
				_make_species(
					&"boulder",
					"Boulder",
					"A heavy stone that needs great force to break.",
					VegetationSpecies.Kind.ROCK,
					0.0,
					0.8,
					1.4,
					true,
					0.5,
					Color(0.40, 0.40, 0.38, 1.0),
					Color(0.40, 0.40, 0.38, 1.0),
					1.0,
					_make_properties(
						1800.0, true, 0.95, false, 0.0, 0.0, 0.0, true, 200_000.0, 60_000.0, 0.0
					)
				),
			]
		)
	)
	_add_rule(
		result,
		&"landuse",
		&"wood",
		&"",
		4.0,
		{
			&"eucalyptus": 3.0,
			&"araucaria": 1.0,
			&"ipe": 1.0,
			&"hibiscus": 1.5,
			&"azalea": 1.5,
			&"rock": 0.3,
		}
	)
	_add_rule(
		result,
		&"landuse",
		&"residential",
		&"",
		0.35,
		{
			&"ipe": 1.0,
			&"jacaranda": 1.0,
			&"eucalyptus": 0.5,
			&"hibiscus": 2.0,
			&"azalea": 2.0,
			&"rock": 0.1,
		}
	)
	_add_rule(
		result,
		&"landuse",
		&"grass",
		&"",
		0.15,
		{
			&"ipe": 1.0,
			&"jacaranda": 1.0,
			&"azalea": 1.0,
		}
	)
	_add_rule(
		result,
		&"landuse",
		&"playground",
		&"",
		0.5,
		{
			&"ipe": 1.0,
			&"eucalyptus": 1.0,
		}
	)
	_add_rule(
		result,
		&"landuse",
		&"yes",
		&"",
		0.4,
		{
			&"ipe": 1.0,
			&"jacaranda": 1.5,
			&"eucalyptus": 1.0,
			&"hibiscus": 1.5,
			&"azalea": 1.0,
		}
	)
	_add_street_rule(
		result,
		&"residential",
		18.0,
		1.8,
		true,
		{
			&"ipe": 2.0,
			&"jacaranda": 2.0,
			&"eucalyptus": 1.0,
		}
	)
	_add_street_rule(
		result,
		&"tertiary",
		18.0,
		1.8,
		true,
		{
			&"ipe": 2.0,
			&"jacaranda": 2.0,
			&"eucalyptus": 1.0,
		}
	)
	return result


## Shared fallback instance for callers that have no authored VegetationRules.
static func shared_default() -> VegetationRules:
	if _shared == null:
		_shared = create_default()
	return _shared


static func _make_properties(
	mass_kg: float,
	movable: bool,
	friction: float,
	flammable: bool,
	ignition_temperature_c: float,
	ignition_energy_j: float,
	heat_release_j_per_kg: float,
	breakable: bool,
	breaking_force_n: float,
	breaking_energy_j: float,
	max_age_years: float
) -> ObjectProperties:
	var properties := ObjectProperties.new()
	properties.mass_kg = mass_kg
	properties.movable = movable
	properties.friction = friction
	properties.flammable = flammable
	properties.ignition_temperature_c = ignition_temperature_c
	properties.ignition_energy_j = ignition_energy_j
	properties.heat_release_j_per_kg = heat_release_j_per_kg
	properties.breakable = breakable
	properties.breaking_force_n = breaking_force_n
	properties.breaking_energy_j = breaking_energy_j
	properties.max_age_years = max_age_years
	return properties


static func _make_species(
	id: StringName,
	display_name: String,
	description: String,
	kind: VegetationSpecies.Kind,
	trunk_radius_m: float,
	radius_min_m: float,
	radius_max_m: float,
	collides: bool,
	clearance_m: float,
	ground_color: Color,
	canopy_color: Color,
	canopy_alpha: float,
	properties: ObjectProperties
) -> VegetationSpecies:
	var entry := VegetationSpecies.new()
	entry.id = id
	entry.display_name = display_name
	entry.description = description
	entry.kind = kind
	entry.trunk_radius_m = trunk_radius_m
	entry.radius_min_m = radius_min_m
	entry.radius_max_m = radius_max_m
	entry.collides = collides
	entry.clearance_m = clearance_m
	entry.ground_color = ground_color
	entry.canopy_color = canopy_color
	entry.canopy_alpha = canopy_alpha
	entry.properties = properties
	return entry


static func _add_rule(
	result: VegetationRules,
	category: StringName,
	kind: StringName,
	surface: StringName,
	density_per_100m2: float,
	species_weights: Dictionary
) -> void:
	var rule := VegetationRule.new()
	rule.category = category
	rule.kind = kind
	rule.surface = surface
	rule.density_per_100m2 = density_per_100m2
	rule.species_weights = species_weights
	result.rules.append(rule)


static func _add_street_rule(
	result: VegetationRules,
	road_kind: StringName,
	spacing_m: float,
	offset_m: float,
	both_sides: bool,
	species_weights: Dictionary
) -> void:
	var rule := StreetTreeRule.new()
	rule.road_kind = road_kind
	rule.spacing_m = spacing_m
	rule.offset_m = offset_m
	rule.both_sides = both_sides
	rule.species_weights = species_weights
	result.street_rules.append(rule)
