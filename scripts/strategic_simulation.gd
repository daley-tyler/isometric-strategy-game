class_name StrategicSimulation
extends RefCounted

const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CombatConfigScript = preload("res://scripts/combat_config.gd")
const StrategicConfigScript = preload("res://scripts/strategic_config.gd")

var map_data
var city_data
var ai_city_data
var combat_data
var tick_count := 0
var silos: Dictionary = {}
var sam_cooldowns: Dictionary = {}
var missiles: Dictionary = {}
var next_missile_id := 1
var last_action_reason := ""
var selected_silo := Vector2i(-1, -1)
var impact_markers: Array[Dictionary] = []

func _init(data, city, combat) -> void:
	map_data = data; city_data = city; combat_data = combat

func ensure_silo(tile: Vector2i) -> Dictionary:
	if not silos.has(tile): silos[tile] = {"stored": 0, "cooldown": 0, "production": 0}
	return silos[tile]

func queue_missile(tile: Vector2i) -> bool:
	if city_data.get_building(tile) != CitySimulationScript.Building.MISSILE_SILO: return reject("Cannot manufacture missile: Select Missile Silo")
	var silo := ensure_silo(tile)
	if int(silo["stored"]) >= StrategicConfigScript.SILO_CAPACITY: return reject("Cannot manufacture missile: Missile storage full")
	if int(silo["production"]) > 0: return reject("Cannot manufacture missile: Silo busy")
	if city_data.get_resource(CitySimulationScript.LedgerResource.MONEY) < StrategicConfigScript.MISSILE_COST_MONEY: return reject("Cannot manufacture missile: Not enough money")
	if city_data.get_resource(CitySimulationScript.LedgerResource.MATERIALS) < StrategicConfigScript.MISSILE_COST_MATERIALS: return reject("Cannot manufacture missile: Not enough materials")
	if city_data.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES) < StrategicConfigScript.MISSILE_COST_SUPPLIES: return reject("Cannot manufacture missile: Not enough military supplies")
	if city_data.get_resource(CitySimulationScript.LedgerResource.ELECTRICITY) < StrategicConfigScript.MISSILE_COST_POWER: return reject("Cannot manufacture missile: No available electricity")
	silo["production"] = StrategicConfigScript.MISSILE_PRODUCTION_TICKS
	return accept("Missile manufacturing started")

func launch_missile(tile: Vector2i, target: Vector2i, owner: int = CombatConfigScript.OWNER_PLAYER) -> bool:
	if not map_data.is_valid(target): return reject("Invalid target")
	if city_data.get_building(tile) != CitySimulationScript.Building.MISSILE_SILO: return reject("Select Missile Silo")
	var silo := ensure_silo(tile)
	if int(silo["stored"]) <= 0: return reject("No missiles stored")
	if int(silo["cooldown"]) > 0: return reject("Silo preparing launch")
	silo["stored"] -= 1; silo["cooldown"] = StrategicConfigScript.SILO_LAUNCH_COOLDOWN
	var missile_id := next_missile_id; next_missile_id += 1
	var duration := StrategicConfigScript.flight_duration_ticks(tile, target)
	missiles[missile_id] = {"id": missile_id, "owner": owner, "source": tile, "target": target, "progress": 0.0, "elapsed": 0, "duration": duration, "alive": true, "intercepted": false}
	return accept("Missile launched")

func tick() -> Array[Vector2i]:
	tick_count += 1
	for marker in impact_markers:
		marker["remaining"] = int(marker["remaining"]) - 1
	impact_markers = impact_markers.filter(func(marker: Dictionary) -> bool: return int(marker["remaining"]) > 0)
	for tile in silos.keys():
		if city_data.get_building(tile) != CitySimulationScript.Building.MISSILE_SILO:
			silos.erase(tile)
			continue
		var silo: Dictionary = silos[tile]
		silo["cooldown"] = maxi(0, int(silo["cooldown"]) - 1)
		if int(silo["production"]) > 0:
			# Like unit manufacturing, pay on completion and wait for resupply
			# if other production or construction has spent the same reserves.
			if int(silo["production"]) == 1 and not missile_resources_available():
				continue
			silo["production"] = int(silo["production"]) - 1
			if int(silo["production"]) == 0:
				city_data.resources[CitySimulationScript.LedgerResource.MONEY] -= StrategicConfigScript.MISSILE_COST_MONEY
				city_data.resources[CitySimulationScript.LedgerResource.MATERIALS] -= StrategicConfigScript.MISSILE_COST_MATERIALS
				city_data.resources[CitySimulationScript.LedgerResource.MILITARY_SUPPLIES] -= StrategicConfigScript.MISSILE_COST_SUPPLIES
				silo["stored"] = mini(StrategicConfigScript.SILO_CAPACITY, int(silo["stored"]) + 1)
	var changed: Array[Vector2i] = []
	run_sams()
	for missile_id in missiles.keys():
		var missile: Dictionary = missiles[missile_id]
		if not bool(missile["alive"]): continue
		missile["elapsed"] = int(missile["elapsed"]) + 1
		missile["progress"] = clampf(float(missile["elapsed"]) / float(missile["duration"]), 0.0, 1.0)
		if int(missile["elapsed"]) >= int(missile["duration"]):
			missile["alive"] = false
			impact_markers.append({"tile": missile["target"], "remaining": 2})
			changed.append_array(apply_blast(missile["target"]))
	return changed

func missile_resources_available() -> bool:
	return city_data.get_resource(CitySimulationScript.LedgerResource.MONEY) >= StrategicConfigScript.MISSILE_COST_MONEY and city_data.get_resource(CitySimulationScript.LedgerResource.MATERIALS) >= StrategicConfigScript.MISSILE_COST_MATERIALS and city_data.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES) >= StrategicConfigScript.MISSILE_COST_SUPPLIES

func run_sams() -> void:
	for tile in city_data.industry_buildings:
		if city_data.get_building(tile) != CitySimulationScript.Building.SAM_SITE or not sam_operational(tile): continue
		var cooldown: int = int(sam_cooldowns.get(tile, 0))
		if cooldown > 0: sam_cooldowns[tile] = cooldown - 1; continue
		for missile_id in missiles.keys():
			var missile: Dictionary = missiles[missile_id]
			if bool(missile["alive"]) and int(missile["owner"]) != CombatConfigScript.OWNER_PLAYER and tile.distance_to(missile_tile(missile)) <= StrategicConfigScript.SAM_RANGE:
				sam_cooldowns[tile] = StrategicConfigScript.SAM_COOLDOWN_TICKS
				if int(missile["id"]) % 2 == 1: missile["alive"] = false; missile["intercepted"] = true
				break
		if int(sam_cooldowns.get(tile, 0)) > 0: continue
		for unit_id in combat_data.sorted_unit_ids():
			var unit: Dictionary = combat_data.units[unit_id]
			if bool(unit["alive"]) and bool(unit["air"]) and int(unit["owner"]) != CombatConfigScript.OWNER_PLAYER and tile.distance_to(unit["tile"]) <= StrategicConfigScript.SAM_RANGE:
				unit["health"] = maxf(0.0, float(unit["health"]) - 12.0); sam_cooldowns[tile] = StrategicConfigScript.SAM_COOLDOWN_TICKS
				if float(unit["health"]) <= 0.0: unit["alive"] = false
				break

func sam_operational(tile: Vector2i) -> bool:
	return city_data.has_power(tile) and city_data.has_road_access(tile) and not city_data.has_rubble(tile)

func missile_tile(missile: Dictionary) -> Vector2i:
	var ratio := clampf(float(missile["progress"]), 0.0, 1.0)
	var source: Vector2 = Vector2(missile["source"])
	var target: Vector2 = Vector2(missile["target"])
	return Vector2i(source.lerp(target, ratio).round())

func missile_visual_progress(missile: Dictionary) -> float:
	return clampf(float(missile["progress"]), 0.0, 1.0)

func missile_duration_ticks(source: Vector2i, target: Vector2i) -> int:
	return StrategicConfigScript.flight_duration_ticks(source, target)

func missile_eta_seconds(source: Vector2i, target: Vector2i) -> float:
	return float(missile_duration_ticks(source, target))

func missile_visual_position(missile: Dictionary) -> Vector2:
	var progress := missile_visual_progress(missile)
	return StrategicConfigScript.ballistic_world_position(Vector2i(missile["source"]), Vector2i(missile["target"]), progress)

func blast_tiles(center: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in range(center.y - StrategicConfigScript.MISSILE_BLAST_RADIUS, center.y + StrategicConfigScript.MISSILE_BLAST_RADIUS + 1):
		for x in range(center.x - StrategicConfigScript.MISSILE_BLAST_RADIUS, center.x + StrategicConfigScript.MISSILE_BLAST_RADIUS + 1):
			var tile := Vector2i(x, y)
			if map_data.is_valid(tile) and tile.distance_to(center) <= StrategicConfigScript.MISSILE_BLAST_RADIUS: tiles.append(tile)
	return tiles

func apply_blast(center: Vector2i) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	for tile in blast_tiles(center):
		for unit_id in combat_data.sorted_unit_ids():
			var unit: Dictionary = combat_data.units[unit_id]
			if bool(unit["alive"]) and unit["tile"] == tile: unit["health"] = 0.0; unit["alive"] = false
		# Missile effects are area effects.  Both nations use the same damage
		# rule, so an AI city is neither immune nor a special target.
		city_data.destroy_structure(tile)
		if ai_city_data != null:
			ai_city_data.destroy_structure(tile)
		map_data.mark_scorched(tile)
		changed.append(tile)
	return changed

func silo_summary(tile: Vector2i) -> String:
	if city_data.get_building(tile) != CitySimulationScript.Building.MISSILE_SILO: return ""
	var silo := ensure_silo(tile)
	return "Silo: %d/%d missiles · production %d · cooldown %d" % [int(silo["stored"]), StrategicConfigScript.SILO_CAPACITY, int(silo["production"]), int(silo["cooldown"])]

func sam_summary(tile: Vector2i) -> String:
	if city_data.get_building(tile) != CitySimulationScript.Building.SAM_SITE: return ""
	return "SAM: %s · range %d · cooldown %d" % ["Operational" if sam_operational(tile) else "No power/access", StrategicConfigScript.SAM_RANGE, int(sam_cooldowns.get(tile, 0))]

func accept(message: String) -> bool: last_action_reason = message; return true
func reject(message: String) -> bool: last_action_reason = message; return false
