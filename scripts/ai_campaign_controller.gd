class_name AICampaignController
extends RefCounted

const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CombatConfigScript = preload("res://scripts/combat_config.gd")

# This is intentionally a small, deterministic campaign policy.  It owns no
# alternate rules: its economy is a normal CitySimulation and every order is
# issued through CombatSimulation.
enum Phase { BUILD, DEFEND, PREPARE, ATTACK, RECOVER }

const DECISION_INTERVAL_TICKS := 3
const MAX_UNITS := 8
const DEFENSE_RESERVE := 2

var map_data
var economy
var player_city
var combat
var strategic
var phase := Phase.BUILD
var simulation_ticks := 0
var decision_count := 0
var road_cursor := 0
var site_cursor := 0
var road_plan: Array[Vector2i] = []
var building_sites: Array[Vector2i] = []
var current_target := Vector2i(-1, -1)
var last_decision := "Initializing"

func _init(data, player = null, combat_simulation = null, strategic_simulation = null) -> void:
	map_data = data
	economy = CitySimulationScript.new(data)
	configure(player, combat_simulation, strategic_simulation)

func configure(player, combat_simulation, strategic_simulation) -> void:
	player_city = player
	combat = combat_simulation
	strategic = strategic_simulation
	if player_city != null:
		economy.foreign_city_data = player_city
		player_city.foreign_city_data = economy
	if combat != null:
		combat.ai_city_data = economy
	if strategic != null:
		strategic.ai_city_data = economy
	if road_plan.is_empty() and combat != null:
		build_layout()

func tick() -> Array[Vector2i]:
	var changed: Array[Vector2i] = economy.tick()
	simulation_ticks += 1
	if simulation_ticks % DECISION_INTERVAL_TICKS != 0:
		return changed
	decision_count += 1
	changed.append_array(make_decision())
	return changed

func make_decision() -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	if combat == null:
		return changed
	if road_cursor < road_plan.size():
		var road := road_plan[road_cursor]
		road_cursor += 1
		if economy.place_road(road):
			changed.append(road)
			last_decision = "Road access"
		return changed

	# Essential services and workforce precede discretionary spending.
	if ensure_utility(CitySimulationScript.Building.POWER_PLANT, changed, "Power"):
		return changed
	if ensure_utility(CitySimulationScript.Building.WATER_FACILITY, changed, "Water"):
		return changed
	if count_zones(CitySimulationScript.Zone.RESIDENTIAL) < 3:
		if place_next_zone(CitySimulationScript.Zone.RESIDENTIAL, changed, "Housing"):
			return changed
	if count_zones(CitySimulationScript.Zone.COMMERCIAL) < 1:
		if place_next_zone(CitySimulationScript.Zone.COMMERCIAL, changed, "Commerce"):
			return changed
	if ensure_industry(CitySimulationScript.Building.FARM, changed, "Food production"):
		return changed
	if ensure_industry(CitySimulationScript.Building.IMPORT_DEPOT, changed, "Import depot"):
		return changed
	if ensure_industry(CitySimulationScript.Building.BARRACKS, changed, "Barracks"):
		return changed
	if ensure_industry(CitySimulationScript.Building.UNIVERSITY, changed, "University"):
		return changed
	if ensure_utility(CitySimulationScript.Building.FIRE_STATION, changed, "Fire coverage"):
		return changed

	# Imports remain ordinary paid orders and only cover short prototype reserves.
	if order_needed_import():
		return changed
	if economy.active_technology == CitySimulationScript.Technology.NONE and economy.start_next_research():
		last_decision = "Research: %s" % economy.last_action_reason
		return changed
	if economy.is_technology_unlocked(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION):
		if ensure_industry(CitySimulationScript.Building.RESEARCH_LAB, changed, "Research lab"):
			return changed
	if economy.is_technology_unlocked(CitySimulationScript.Technology.ADVANCED_MANUFACTURING):
		if ensure_industry(CitySimulationScript.Building.VEHICLE_FACTORY, changed, "Vehicle factory"):
			return changed
	if economy.is_technology_unlocked(CitySimulationScript.Technology.AUTOMATION):
		if ensure_industry(CitySimulationScript.Building.DRONE_FACTORY, changed, "Drone factory"):
			return changed
	if economy.is_technology_unlocked(CitySimulationScript.Technology.AEROSPACE):
		if ensure_industry(CitySimulationScript.Building.AIRBASE, changed, "Airbase"):
			return changed
	if economy.is_technology_unlocked(CitySimulationScript.Technology.NEAR_FUTURE):
		if ensure_industry(CitySimulationScript.Building.SAM_SITE, changed, "SAM site"):
			return changed

	deploy_completed_units()
	var unit_count := alive_ai_units().size()
	if unit_count < MAX_UNITS and queue_next_unit():
		return changed
	assign_force_orders()
	return changed

func build_layout() -> void:
	var route: Array[Vector2i] = combat.find_path(map_data.ai_capital, map_data.player_capital, false)
	for tile in route:
		if tile != map_data.ai_capital and road_plan.size() < 12:
			road_plan.append(tile)
	var reserved := {}
	for tile in road_plan:
		reserved[tile] = true
	for road in road_plan:
		for direction in map_data.CARDINAL_DIRECTIONS:
			var site: Vector2i = road + direction
			if building_sites.size() >= 18:
				break
			if map_data.is_land(site) and site != map_data.player_capital and site != map_data.ai_capital and not reserved.has(site):
				reserved[site] = true
				building_sites.append(site)
	# A valid connected map always has a path, but retain a bounded fallback for
	# custom development seeds with a short route.
	if building_sites.size() < 12:
		for y in range(maxi(0, map_data.ai_capital.y - 8), mini(map_data.size.y, map_data.ai_capital.y + 9)):
			for x in range(maxi(0, map_data.ai_capital.x - 8), mini(map_data.size.x, map_data.ai_capital.x + 9)):
				var candidate := Vector2i(x, y)
				if building_sites.size() >= 18:
					break
				if map_data.is_land(candidate) and candidate != map_data.ai_capital and not reserved.has(candidate):
					reserved[candidate] = true
					building_sites.append(candidate)

func ensure_utility(building_type: int, changed: Array[Vector2i], label: String) -> bool:
	if has_building(building_type):
		return false
	return place_next_building(building_type, changed, label, true)

func ensure_industry(building_type: int, changed: Array[Vector2i], label: String) -> bool:
	if has_building(building_type):
		return false
	return place_next_building(building_type, changed, label, false)

func place_next_building(building_type: int, changed: Array[Vector2i], label: String, utility: bool) -> bool:
	var site := next_site()
	if site.x < 0:
		last_decision = "No valid building site"
		return false
	var placed: bool = economy.place_utility(site, building_type) if utility else economy.place_industry_building(site, building_type)
	if placed:
		changed.append(site)
		last_decision = label
		return true
	# Keep a site only for this decision; a shortage must not cause repeated
	# placement attempts or skip all future candidate sites forever.
	return false

func place_next_zone(zone_type: int, changed: Array[Vector2i], label: String) -> bool:
	var site := next_site()
	if site.x < 0:
		return false
	if economy.place_zone(site, zone_type):
		changed.append(site)
		last_decision = label
		return true
	return false

func next_site() -> Vector2i:
	while site_cursor < building_sites.size():
		var site := building_sites[site_cursor]
		site_cursor += 1
		if economy.can_place_manual_building(site):
			return site
	return Vector2i(-1, -1)

func count_zones(zone_type: int) -> int:
	var count := 0
	for value in economy.zones:
		if int(value) == zone_type:
			count += 1
	return count

func has_building(building_type: int) -> bool:
	for value in economy.buildings:
		if int(value) == building_type:
			return true
	return false

func building_tile(building_type: int) -> Vector2i:
	for tile in economy.industry_buildings:
		if economy.get_building(tile) == building_type:
			return tile
	return Vector2i(-1, -1)

func order_needed_import() -> bool:
	if not economy.has_operational_import_depot():
		return false
	var needs := [
		[CitySimulationScript.LedgerResource.FOOD, 30.0],
		[CitySimulationScript.LedgerResource.MATERIALS, 8.0],
		[CitySimulationScript.LedgerResource.FUEL, 5.0],
		[CitySimulationScript.LedgerResource.MILITARY_SUPPLIES, 6.0],
	]
	for entry in needs:
		var resource: int = int(entry[0])
		if economy.get_resource(resource) < float(entry[1]) and not has_import_order(resource):
			if economy.place_import_order(resource):
				last_decision = "Importing %s" % economy.resource_name(resource)
				return true
	return false

func has_import_order(resource: int) -> bool:
	for order in economy.import_orders:
		if int(order["resource"]) == resource:
			return true
	return false

func deploy_completed_units() -> void:
	for unit_type in range(CitySimulationScript.UnitType.INFANTRY, CitySimulationScript.UnitType.FIGHTER + 1):
		var facility: Vector2i = building_tile(int(economy.unit_definition(unit_type).get("facility", -1)))
		if facility.x >= 0 and economy.get_produced_unit_count(unit_type) > 0:
			if combat.deploy_produced_unit_for_owner(economy, CombatConfigScript.OWNER_AI, unit_type, facility):
				var unit_id: int = combat.next_unit_id - 1
				combat.units[unit_id]["strategic_managed"] = true
				last_decision = "Deployed %s" % economy.unit_name(unit_type)

func queue_next_unit() -> bool:
	var composition := unit_composition()
	var candidates := [CitySimulationScript.UnitType.INFANTRY]
	if economy.is_technology_unlocked(CitySimulationScript.Technology.ADVANCED_MANUFACTURING):
		candidates.append(CitySimulationScript.UnitType.TANK)
		candidates.append(CitySimulationScript.UnitType.ARTILLERY)
	if economy.is_technology_unlocked(CitySimulationScript.Technology.AUTOMATION):
		candidates.append(CitySimulationScript.UnitType.RECON_DRONE)
		candidates.append(CitySimulationScript.UnitType.ROBOT_UNIT)
	if economy.is_technology_unlocked(CitySimulationScript.Technology.AEROSPACE):
		candidates.append(CitySimulationScript.UnitType.FIGHTER)
		candidates.append(CitySimulationScript.UnitType.BOMBER)
	for unit_type in candidates:
		var facility := building_tile(int(economy.unit_definition(unit_type).get("facility", -1)))
		if facility.x >= 0 and not economy.has_manufacturing_order(facility):
			# Infantry is the affordable defensive baseline; later types fill gaps.
			if int(composition.get(unit_type, 0)) <= int(composition.get(CitySimulationScript.UnitType.INFANTRY, 0)) or unit_type == CitySimulationScript.UnitType.INFANTRY:
				if economy.queue_unit(facility, unit_type):
					last_decision = "Manufacturing %s" % economy.unit_name(unit_type)
					return true
	return false

func unit_composition() -> Dictionary:
	var result := {}
	for unit_id in combat.sorted_unit_ids():
		var unit: Dictionary = combat.get_unit(unit_id)
		if bool(unit.get("alive", false)) and int(unit.get("owner", 0)) == CombatConfigScript.OWNER_AI:
			var unit_type := int(unit["type"])
			result[unit_type] = int(result.get(unit_type, 0)) + 1
	return result

func alive_ai_units() -> Array[int]:
	var result: Array[int] = []
	for unit_id in combat.sorted_unit_ids():
		var unit: Dictionary = combat.get_unit(unit_id)
		if bool(unit.get("alive", false)) and int(unit.get("owner", 0)) == CombatConfigScript.OWNER_AI:
			result.append(unit_id)
	return result

func assign_force_orders() -> void:
	var units := alive_ai_units()
	if units.size() <= DEFENSE_RESERVE:
		phase = Phase.DEFEND
		for unit_id in units:
			combat.units[unit_id]["strategic_managed"] = true
			combat.issue_defend(unit_id)
		last_decision = "Capital defense"
		return
	current_target = select_target()
	for index in units.size():
		var unit_id: int = units[index]
		combat.units[unit_id]["strategic_managed"] = true
		if index < DEFENSE_RESERVE:
			combat.issue_defend(unit_id)
		elif units.size() >= 5:
			var unit: Dictionary = combat.get_unit(unit_id)
			var path: Array = unit["path"]
			# Keep an existing route and its terrain movement delay. Reissuing
			# the same order rebuilt a full-map BFS every decision interval.
			if int(unit["command"]) != CombatConfigScript.COMMAND_MOVE or path.is_empty() or path.back() != current_target:
				combat.issue_move(unit_id, current_target)
	phase = Phase.ATTACK if units.size() >= 5 else Phase.PREPARE
	last_decision = "Attack force advancing" if phase == Phase.ATTACK else "Preparing attack"

func select_target() -> Vector2i:
	var selected: Vector2i = map_data.player_capital
	var best_distance := 1 << 30
	if player_city != null:
		for tile in player_city.industry_buildings:
			var distance: int = map_data.ai_capital.distance_squared_to(tile)
			if distance < best_distance:
				best_distance = distance
				selected = tile
	return selected

func summary() -> String:
	return "AI: %s · %s · Units %d · $%.0f" % [Phase.keys()[phase], last_decision, alive_ai_units().size(), economy.get_resource(CitySimulationScript.LedgerResource.MONEY)]
