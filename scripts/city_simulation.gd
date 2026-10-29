class_name CitySimulation
extends RefCounted

const CityConfigScript = preload("res://scripts/city_config.gd")

enum Zone { NONE, RESIDENTIAL, COMMERCIAL }
enum Building {
	NONE, POWER_PLANT, WATER_FACILITY, FIRE_STATION, RESIDENTIAL, COMMERCIAL,
	FARM, MATERIALS_PLANT, REFINERY, IMPORT_DEPOT, DEFENSE_FACTORY,
	UNIVERSITY, RESEARCH_LAB, BARRACKS, VEHICLE_FACTORY, DRONE_FACTORY,
	AIRBASE, SAM_SITE, MISSILE_SILO,
}
enum LedgerResource { MONEY, WORKFORCE, ELECTRICITY, FOOD, MATERIALS, FUEL, MILITARY_SUPPLIES }
enum Technology { NONE, INDUSTRIAL_EXPANSION, REFINING, DEFENSE_INDUSTRY, ADVANCED_MANUFACTURING, AUTOMATION, AEROSPACE, NEAR_FUTURE }
enum UnitType { NONE, INFANTRY, TANK, ARTILLERY, ROBOT_UNIT, RECON_DRONE, BOMBER, FIGHTER }

var map_data
# The campaign owns both cities. Occupancy queries must not make them own
# each other, otherwise every restart/load retains two full simulation grids.
var _foreign_city_ref: WeakRef
var foreign_city_data:
	get:
		return _foreign_city_ref.get_ref() if _foreign_city_ref != null else null
	set(value):
		_foreign_city_ref = weakref(value) if value != null else null
var roads := PackedByteArray()
var zones := PackedByteArray()
var buildings := PackedByteArray()
var power_coverage := PackedByteArray()
var water_coverage := PackedByteArray()
var fire_coverage := PackedByteArray()
var rubble := PackedByteArray()
var resources := PackedFloat64Array()
var completed_technologies := PackedByteArray()
var produced_units := PackedInt32Array()
var household_capacity := 0
var occupied_households := 0
var job_capacity := 0
var employed_workforce := 0
var network_dirty := true
var tick_count := 0
var last_action_reason := ""

# These lists change only after construction or bulldozing; economic ticks reuse them.
var industry_buildings: Array[Vector2i] = []
var import_orders: Array[Dictionary] = []
var manufacturing_orders: Array[Dictionary] = []
var production_status := {}
var active_technology := Technology.NONE
var research_progress := 0.0
var research_status := "No active research"
var selected_import_resource := LedgerResource.FOOD
var operation_workforce_remaining := 0
var operation_power_remaining := 0.0

func _init(data) -> void:
	map_data = data
	var count: int = data.size.x * data.size.y
	roads.resize(count)
	zones.resize(count)
	buildings.resize(count)
	power_coverage.resize(count)
	water_coverage.resize(count)
	fire_coverage.resize(count)
	rubble.resize(count)
	resources.resize(7)
	completed_technologies.resize(CityConfigScript.TECH_COUNT)
	produced_units.resize(CityConfigScript.UNIT_COUNT)
	resources[LedgerResource.MONEY] = CityConfigScript.STARTING_MONEY
	resources[LedgerResource.FOOD] = 100.0

func index(tile: Vector2i) -> int:
	return map_data.index(tile)

func has_road(tile: Vector2i) -> bool:
	return map_data.is_valid(tile) and roads[index(tile)] != 0

func get_zone(tile: Vector2i) -> int:
	return zones[index(tile)] if map_data.is_valid(tile) else Zone.NONE

func get_building(tile: Vector2i) -> int:
	return buildings[index(tile)] if map_data.is_valid(tile) else Building.NONE

func has_rubble(tile: Vector2i) -> bool:
	return map_data.is_valid(tile) and rubble[index(tile)] != 0

func has_road_access(tile: Vector2i) -> bool:
	for direction in map_data.CARDINAL_DIRECTIONS:
		if has_road(tile + direction):
			return true
	return false

func can_place_road(tile: Vector2i) -> bool:
	return map_data.is_traversable_ground(tile) and not has_rubble(tile) and not has_road(tile) and get_zone(tile) == Zone.NONE and get_building(tile) == Building.NONE and not foreign_occupied(tile)

func place_road(tile: Vector2i) -> bool:
	if not map_data.is_valid(tile) or not map_data.is_traversable_ground(tile):
		return reject_action("Cannot build: Invalid terrain")
	if has_rubble(tile):
		return reject_action("Cannot build: Rubble must be cleared")
	if has_road(tile) or get_zone(tile) != Zone.NONE or get_building(tile) != Building.NONE or foreign_occupied(tile):
		return reject_action("Cannot build: Occupied tile")
	roads[index(tile)] = 1
	network_dirty = true
	return accept_action("Road placed")

func place_zone(tile: Vector2i, zone_type: int) -> bool:
	if zone_type == Zone.NONE or (zone_type != Zone.RESIDENTIAL and zone_type != Zone.COMMERCIAL):
		return reject_action("Cannot zone: Invalid placement")
	if not map_data.is_valid(tile) or not map_data.is_land(tile):
		return reject_action("Cannot zone: Invalid terrain")
	if has_rubble(tile):
		return reject_action("Cannot zone: Rubble must be cleared")
	if has_road(tile) or get_zone(tile) != Zone.NONE or get_building(tile) != Building.NONE or foreign_occupied(tile):
		return reject_action("Cannot zone: Occupied tile")
	zones[index(tile)] = zone_type
	return accept_action("Residential zone placed" if zone_type == Zone.RESIDENTIAL else "Commercial zone placed")

func place_utility(tile: Vector2i, building_type: int) -> bool:
	if building_type != Building.POWER_PLANT and building_type != Building.WATER_FACILITY and building_type != Building.FIRE_STATION:
		return reject_action("Cannot build: Invalid placement")
	var reason := building_placement_reason(tile, building_type)
	if not reason.is_empty():
		return reject_action(reason)
	var cost := utility_cost(building_type)
	if resources[LedgerResource.MONEY] < cost:
		return reject_action("Cannot build: Not enough money")
	buildings[index(tile)] = building_type
	resources[LedgerResource.MONEY] -= cost
	network_dirty = true
	return accept_action(utility_name(building_type) + " placed")

func place_industry_building(tile: Vector2i, building_type: int) -> bool:
	var definition: Dictionary = building_definition(building_type)
	if definition.is_empty():
		return reject_action("Cannot build: Invalid placement")
	var reason := building_placement_reason(tile, building_type)
	if not reason.is_empty():
		return reject_action(reason)
	var money_cost: float = float(definition.get("money_cost", 0.0))
	var material_cost: float = float(definition.get("material_cost", 0.0))
	if resources[LedgerResource.MONEY] < money_cost:
		return reject_action("Cannot build: Not enough money")
	if resources[LedgerResource.MATERIALS] < material_cost:
		return reject_action("Cannot build: Not enough materials")
	buildings[index(tile)] = building_type
	resources[LedgerResource.MONEY] -= money_cost
	resources[LedgerResource.MATERIALS] -= material_cost
	industry_buildings.append(tile)
	return accept_action("%s placed" % String(definition.get("name", "Building")))

func can_place_manual_building(tile: Vector2i) -> bool:
	var reason := building_site_reason(tile)
	if not reason.is_empty():
		return reject_action(reason)
	return true

func get_building_footprint_tiles(_building_type: int, anchor_tile: Vector2i) -> Array[Vector2i]:
	return [anchor_tile]

func building_site_reason(tile: Vector2i) -> String:
	if not map_data.is_valid(tile): return "Cannot build: Invalid terrain"
	if not map_data.is_land(tile): return "Cannot build: Water"
	if has_rubble(tile) or (foreign_city_data != null and foreign_city_data.has_rubble(tile)):
		return "Cannot build: Rubble must be cleared"
	if has_road(tile) or (foreign_city_data != null and foreign_city_data.has_road(tile)):
		return "Cannot build: Road occupies tile"
	if get_building(tile) != Building.NONE or (foreign_city_data != null and foreign_city_data.get_building(tile) != Building.NONE):
		return "Cannot build: Existing building"
	if get_zone(tile) != Zone.NONE or foreign_occupied(tile): return "Cannot build: Occupied tile"
	return ""

# Read-only validation shared by ghosts and all construction entry points.
func building_placement_reason(tile: Vector2i, building_type: int) -> String:
	var utility := building_type in [Building.POWER_PLANT, Building.WATER_FACILITY, Building.FIRE_STATION]
	var definition: Dictionary = building_definition(building_type)
	if not utility and definition.is_empty(): return "Cannot build: Invalid placement"
	for footprint_tile in get_building_footprint_tiles(building_type, tile):
		var reason := building_site_reason(footprint_tile)
		if not reason.is_empty(): return reason
	if not utility:
		if not is_technology_unlocked(int(definition.get("unlock", Technology.NONE))): return "Cannot build: Technology not researched"
		if definition.has("deposit") and not has_required_deposit(tile, definition["deposit"]): return "Cannot build: Missing resource deposit"
	var cost: float = utility_cost(building_type) if utility else float(definition.get("money_cost", 0.0))
	if resources[LedgerResource.MONEY] < cost: return "Cannot build: Not enough money"
	if not utility and resources[LedgerResource.MATERIALS] < float(definition.get("material_cost", 0.0)): return "Cannot build: Not enough materials"
	return ""

func foreign_occupied(tile: Vector2i) -> bool:
	return foreign_city_data != null and (foreign_city_data.has_road(tile) or foreign_city_data.get_zone(tile) != Zone.NONE or foreign_city_data.get_building(tile) != Building.NONE or foreign_city_data.has_rubble(tile))

func bulldoze(tile: Vector2i) -> bool:
	if not map_data.is_valid(tile):
		return reject_action("Cannot bulldoze: Invalid placement")
	var changed := false
	if has_rubble(tile):
		rubble[index(tile)] = 0
		return accept_action("Rubble cleared")
	if get_building(tile) != Building.NONE:
		var previous_building := get_building(tile)
		buildings[index(tile)] = Building.NONE
		remove_industry_building(tile)
		remove_orders_at(tile)
		changed = true
		if previous_building == Building.POWER_PLANT or previous_building == Building.WATER_FACILITY or previous_building == Building.FIRE_STATION:
			network_dirty = true
	elif get_zone(tile) != Zone.NONE:
		zones[index(tile)] = Zone.NONE
		changed = true
	elif has_road(tile):
		roads[index(tile)] = 0
		changed = true
		network_dirty = true
	if not changed:
		return reject_action("Cannot bulldoze: Nothing here")
	return accept_action("Removed")

func has_power(tile: Vector2i) -> bool:
	return has_service(power_coverage, tile)

func has_water(tile: Vector2i) -> bool:
	return has_service(water_coverage, tile)

func has_fire_coverage(tile: Vector2i) -> bool:
	return has_service(fire_coverage, tile)

func shortage_reason(tile: Vector2i) -> String:
	if get_zone(tile) == Zone.NONE or get_building(tile) != Building.NONE:
		return ""
	if not has_road_access(tile):
		return "No road access"
	if not has_power(tile):
		return "No power"
	if not has_water(tile):
		return "No water"
	if get_zone(tile) == Zone.COMMERCIAL and occupied_households == 0:
		return "No demand"
	return ""

func tick() -> Array[Vector2i]:
	if network_dirty:
		rebuild_coverage()
	var changed := develop_zones()
	recalculate_totals()
	run_imports()
	run_research()
	run_industry_production()
	run_manufacturing()
	resources[LedgerResource.ELECTRICITY] = maxf(0.0, operation_power_remaining)
	resources[LedgerResource.FOOD] = maxf(0.0, resources[LedgerResource.FOOD] - occupied_households * 0.05)
	resources[LedgerResource.MONEY] += occupied_households * CityConfigScript.TAX_PER_OCCUPIED_HOUSEHOLD
	tick_count += 1
	return changed

func develop_zones() -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if get_zone(tile) != Zone.NONE and get_building(tile) == Building.NONE and shortage_reason(tile).is_empty():
				buildings[index(tile)] = Building.RESIDENTIAL if get_zone(tile) == Zone.RESIDENTIAL else Building.COMMERCIAL
				changed.append(tile)
	return changed

func rebuild_coverage() -> void:
	power_coverage = build_road_coverage(Building.POWER_PLANT)
	water_coverage = build_road_coverage(Building.WATER_FACILITY)
	fire_coverage = build_road_coverage(Building.FIRE_STATION)
	network_dirty = false

func build_road_coverage(source_type: int) -> PackedByteArray:
	var coverage := PackedByteArray()
	coverage.resize(map_data.size.x * map_data.size.y)
	var queue: Array[Vector2i] = []
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if get_building(tile) == source_type:
				coverage[index(tile)] = 1
				for direction in map_data.CARDINAL_DIRECTIONS:
					var road_tile: Vector2i = tile + direction
					if has_road(road_tile) and coverage[index(road_tile)] == 0:
						coverage[index(road_tile)] = 1
						queue.append(road_tile)
	var cursor := 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction in map_data.CARDINAL_DIRECTIONS:
			var next: Vector2i = current + direction
			if has_road(next) and coverage[index(next)] == 0:
				coverage[index(next)] = 1
				queue.append(next)
	return coverage

func recalculate_totals() -> void:
	household_capacity = 0
	job_capacity = 0
	var power_capacity := 0.0
	var zone_power_use := 0.0
	for building in buildings:
		match building:
			Building.RESIDENTIAL:
				household_capacity += CityConfigScript.RESIDENTIAL_CAPACITY
				zone_power_use += CityConfigScript.POWER_PER_DEVELOPMENT
			Building.COMMERCIAL:
				job_capacity += CityConfigScript.COMMERCIAL_JOBS
				zone_power_use += CityConfigScript.POWER_PER_DEVELOPMENT
			Building.POWER_PLANT:
				power_capacity += CityConfigScript.POWER_CAPACITY
	occupied_households = mini(household_capacity, occupied_households + 1)
	var commercial_workforce := mini(occupied_households, job_capacity)
	employed_workforce = commercial_workforce
	operation_workforce_remaining = maxi(0, occupied_households - commercial_workforce)
	operation_power_remaining = maxf(0.0, power_capacity - zone_power_use)
	resources[LedgerResource.WORKFORCE] = float(occupied_households)
	resources[LedgerResource.ELECTRICITY] = operation_power_remaining

func run_imports() -> void:
	var remaining_orders: Array[Dictionary] = []
	for entry in import_orders:
		var order: Dictionary = entry
		var remaining: int = int(order["remaining"])
		if remaining > 1:
			order["remaining"] = remaining - 1
			remaining_orders.append(order)
		else:
			var resource: int = int(order["resource"])
			resources[resource] += float(order["quantity"])
	import_orders = remaining_orders

func run_research() -> void:
	if active_technology == Technology.NONE:
		research_status = "No active research"
		return
	var total_rate := 0.0
	var contributing_buildings := 0
	var required_facility := research_facility_for(active_technology)
	for entry in industry_buildings:
		var tile: Vector2i = entry
		var building_type := get_building(tile)
		if building_type != Building.UNIVERSITY and building_type != Building.RESEARCH_LAB:
			continue
		if required_facility == Building.RESEARCH_LAB and building_type != Building.RESEARCH_LAB:
			continue
		var definition: Dictionary = building_definition(building_type)
		var reason := claim_operation(tile, definition)
		if not reason.is_empty():
			production_status[index(tile)] = reason
			continue
		var contribution: float = float(definition.get("research_rate", 0.0)) / (1.0 + 0.4 * contributing_buildings)
		total_rate += contribution
		contributing_buildings += 1
		production_status[index(tile)] = "Researching %s" % technology_name(active_technology)
	if total_rate <= 0.0:
		research_status = "Research stalled: Requires staffed University or Research Laboratory"
		return
	research_progress += total_rate
	var tech_data: Dictionary = technology_definition(active_technology)
	var required: float = float(tech_data.get("cost", 1.0))
	research_status = "Researching %s: %.1f/%.1f" % [technology_name(active_technology), research_progress, required]
	if research_progress >= required:
		completed_technologies[active_technology] = 1
		research_status = "Completed: %s" % technology_name(active_technology)
		active_technology = Technology.NONE
		research_progress = 0.0

func run_industry_production() -> void:
	for entry in industry_buildings:
		var tile: Vector2i = entry
		var building_type := get_building(tile)
		var definition: Dictionary = building_definition(building_type)
		if definition.is_empty() or not definition.has("output"):
			continue
		var input_resource: int = int(definition.get("input", -1))
		var input_rate: float = float(definition.get("input_rate", 0.0))
		var operating_money: float = float(definition.get("operating_money", 0.0))
		if input_resource >= 0 and resources[input_resource] < input_rate:
			production_status[index(tile)] = "Not enough %s" % resource_name(input_resource)
			continue
		if resources[LedgerResource.MONEY] < operating_money:
			production_status[index(tile)] = "Not enough money"
			continue
		var reason := claim_operation(tile, definition)
		if not reason.is_empty():
			production_status[index(tile)] = reason
			continue
		if input_resource >= 0:
			resources[input_resource] -= input_rate
		resources[LedgerResource.MONEY] -= operating_money
		var output_resource: int = int(definition["output"])
		var rate: float = float(definition.get("rate", 0.0))
		resources[output_resource] += rate
		production_status[index(tile)] = "Producing %s +%.1f/tick" % [resource_name(output_resource), rate]

func run_manufacturing() -> void:
	var remaining_orders: Array[Dictionary] = []
	for entry in manufacturing_orders:
		var order: Dictionary = entry
		var tile: Vector2i = order["tile"]
		var unit_type: int = int(order["unit"])
		if get_building(tile) == Building.NONE:
			continue
		var unit_data: Dictionary = unit_definition(unit_type)
		var building_data: Dictionary = building_definition(get_building(tile))
		var reason := claim_operation(tile, building_data, int(unit_data.get("workforce", 0)), float(unit_data.get("power", 0.0)))
		if not reason.is_empty():
			production_status[index(tile)] = reason
			remaining_orders.append(order)
			continue
		var ticks_remaining: int = int(order["remaining"]) - 1
		if ticks_remaining > 0:
			order["remaining"] = ticks_remaining
			production_status[index(tile)] = "%s: %d tick(s) remaining" % [unit_name(unit_type), ticks_remaining]
			remaining_orders.append(order)
			continue
		var resource_reason := unit_resource_reason(unit_data)
		if not resource_reason.is_empty():
			production_status[index(tile)] = resource_reason
			order["remaining"] = 0
			remaining_orders.append(order)
			continue
		deduct_unit_resources(unit_data)
		produced_units[unit_type] += 1
		production_status[index(tile)] = "Completed %s" % unit_name(unit_type)
	manufacturing_orders = remaining_orders

func claim_operation(tile: Vector2i, definition: Dictionary, extra_workforce: int = 0, extra_power: float = 0.0) -> String:
	var static_reason := static_operation_reason(tile, definition)
	if not static_reason.is_empty():
		return static_reason
	var workforce_needed: int = int(definition.get("workforce", 0)) + extra_workforce
	var power_needed: float = float(definition.get("power", 0.0)) + extra_power
	if operation_workforce_remaining < workforce_needed:
		return "Not enough workers"
	if operation_power_remaining < power_needed:
		return "No available electricity"
	operation_workforce_remaining -= workforce_needed
	employed_workforce += workforce_needed
	operation_power_remaining -= power_needed
	return ""

func static_operation_reason(tile: Vector2i, definition: Dictionary) -> String:
	if has_rubble(tile):
		return "Destroyed"
	if bool(definition.get("road", false)) and not has_road_access(tile):
		return "No road access"
	if bool(definition.get("water", false)) and not has_water(tile):
		return "No water"
	if float(definition.get("power", 0.0)) > 0.0 and not has_power(tile):
		return "No power"
	return ""

func place_import_order(resource: int, quantity: float = CityConfigScript.IMPORT_QUANTITY) -> bool:
	if not CityConfigScript.IMPORT_PRICES.has(resource):
		return reject_action("Cannot import: Invalid resource")
	if quantity <= 0.0:
		return reject_action("Cannot import: Invalid quantity")
	if not has_operational_import_depot():
		return reject_action("Cannot import: Requires Import Depot")
	var cost: float = float(CityConfigScript.IMPORT_PRICES[resource]) * quantity
	if resources[LedgerResource.MONEY] < cost:
		return reject_action("Cannot import: Not enough money")
	resources[LedgerResource.MONEY] -= cost
	import_orders.append({"resource": resource, "quantity": quantity, "cost": cost, "remaining": CityConfigScript.IMPORT_DELAY_TICKS})
	return accept_action("Import ordered: %s" % resource_name(resource))

func cycle_import_resource() -> int:
	var options := [LedgerResource.FOOD, LedgerResource.MATERIALS, LedgerResource.FUEL, LedgerResource.MILITARY_SUPPLIES]
	var current := options.find(selected_import_resource)
	selected_import_resource = options[(current + 1) % options.size()]
	last_action_reason = "Import selected: %s" % resource_name(selected_import_resource)
	return selected_import_resource

func has_operational_import_depot() -> bool:
	for entry in industry_buildings:
		var tile: Vector2i = entry
		if get_building(tile) == Building.IMPORT_DEPOT and static_operation_reason(tile, building_definition(Building.IMPORT_DEPOT)).is_empty():
			return true
	return false

func start_research(technology: int) -> bool:
	if technology <= Technology.NONE or technology >= CityConfigScript.TECH_COUNT:
		return reject_action("Cannot research: Invalid technology")
	if active_technology != Technology.NONE:
		return reject_action("Cannot research: Research already active")
	if is_technology_unlocked(technology):
		return reject_action("Cannot research: Already completed")
	var definition: Dictionary = technology_definition(technology)
	if not is_technology_unlocked(int(definition.get("prerequisite", Technology.NONE))):
		return reject_action("Cannot research: Missing prerequisite technology")
	var required_facility := research_facility_for(technology)
	if not has_research_facility_for(technology):
		return reject_action("Cannot research: Requires %s" % building_name(required_facility))
	active_technology = technology
	research_progress = 0.0
	research_status = "Researching %s" % technology_name(technology)
	return accept_action("Research started: %s" % technology_name(technology))

func start_next_research() -> bool:
	var blocked_reason := ""
	for technology in range(Technology.INDUSTRIAL_EXPANSION, CityConfigScript.TECH_COUNT):
		if not is_technology_unlocked(technology):
			var definition: Dictionary = technology_definition(technology)
			if is_technology_unlocked(int(definition.get("prerequisite", Technology.NONE))):
				if has_research_facility_for(technology):
					return start_research(technology)
				if blocked_reason.is_empty():
					blocked_reason = "Cannot research: Requires %s" % building_name(research_facility_for(technology))
			elif blocked_reason.is_empty():
				blocked_reason = "Cannot research: Requires %s" % technology_name(int(definition.get("prerequisite", Technology.NONE)))
	if not blocked_reason.is_empty():
		return reject_action(blocked_reason)
	return reject_action("Cannot research: All technologies completed")

func has_research_facility() -> bool:
	for entry in industry_buildings:
		var tile: Vector2i = entry
		var building_type := get_building(tile)
		if (building_type == Building.UNIVERSITY or building_type == Building.RESEARCH_LAB) and static_operation_reason(tile, building_definition(building_type)).is_empty():
			return true
	return false

func research_facility_for(technology: int) -> int:
	var definition: Dictionary = technology_definition(technology)
	return int(definition.get("facility", Building.UNIVERSITY))

func has_research_facility_for(technology: int) -> bool:
	var required_facility := research_facility_for(technology)
	for entry in industry_buildings:
		var tile: Vector2i = entry
		var building_type := get_building(tile)
		var can_research := building_type == required_facility or (required_facility == Building.UNIVERSITY and building_type == Building.RESEARCH_LAB)
		if can_research and static_operation_reason(tile, building_definition(building_type)).is_empty():
			return true
	return false

func is_technology_unlocked(technology: int) -> bool:
	return technology == Technology.NONE or (technology >= 0 and technology < completed_technologies.size() and completed_technologies[technology] != 0)

func queue_unit(tile: Vector2i, unit_type: int) -> bool:
	var definition: Dictionary = unit_definition(unit_type)
	if definition.is_empty():
		return reject_action("Cannot manufacture: Invalid unit")
	var required_facility: int = int(definition["facility"])
	if get_building(tile) != required_facility:
		return reject_action("Cannot manufacture: Requires %s" % building_name(required_facility))
	var facility_reason := static_operation_reason(tile, building_definition(required_facility))
	if not facility_reason.is_empty():
		return reject_action("Cannot manufacture: %s" % facility_reason)
	if not is_technology_unlocked(int(definition.get("tech", Technology.NONE))):
		return reject_action("Cannot manufacture: Technology not researched")
	if has_manufacturing_order(tile):
		return reject_action("Cannot manufacture: Facility busy")
	var resource_reason := unit_resource_reason(definition)
	if not resource_reason.is_empty():
		return reject_action("Cannot manufacture: %s" % resource_reason)
	var workforce_needed: int = int(definition.get("workforce", 0)) + int(building_definition(required_facility).get("workforce", 0))
	if maxi(0, occupied_households - employed_workforce) < workforce_needed:
		return reject_action("Cannot manufacture: Not enough workforce")
	var power_needed: float = float(definition.get("power", 0.0)) + float(building_definition(required_facility).get("power", 0.0))
	if resources[LedgerResource.ELECTRICITY] < power_needed:
		return reject_action("Cannot manufacture: No available electricity")
	manufacturing_orders.append({"tile": tile, "unit": unit_type, "remaining": int(definition["ticks"])})
	production_status[index(tile)] = "%s: %d tick(s) remaining" % [unit_name(unit_type), int(definition["ticks"])]
	return accept_action("Manufacturing queued: %s" % unit_name(unit_type))

func has_manufacturing_order(tile: Vector2i) -> bool:
	for entry in manufacturing_orders:
		var order: Dictionary = entry
		if order["tile"] == tile:
			return true
	return false

func unit_resource_reason(definition: Dictionary) -> String:
	if resources[LedgerResource.MONEY] < float(definition.get("money", 0.0)):
		return "Not enough money"
	if resources[LedgerResource.MATERIALS] < float(definition.get("materials", 0.0)):
		return "Not enough materials"
	if resources[LedgerResource.FUEL] < float(definition.get("fuel", 0.0)):
		return "Not enough fuel"
	if resources[LedgerResource.MILITARY_SUPPLIES] < float(definition.get("supplies", 0.0)):
		return "Not enough military supplies"
	return ""

func deduct_unit_resources(definition: Dictionary) -> void:
	resources[LedgerResource.MONEY] -= float(definition.get("money", 0.0))
	resources[LedgerResource.MATERIALS] -= float(definition.get("materials", 0.0))
	resources[LedgerResource.FUEL] -= float(definition.get("fuel", 0.0))
	resources[LedgerResource.MILITARY_SUPPLIES] -= float(definition.get("supplies", 0.0))

func get_resource(resource: int) -> float:
	return resources[resource] if resource >= 0 and resource < resources.size() else 0.0

func get_produced_unit_count(unit_type: int) -> int:
	return produced_units[unit_type] if unit_type >= 0 and unit_type < produced_units.size() else 0

func get_building_status(tile: Vector2i) -> String:
	var active_order := manufacturing_order_at(tile)
	if not active_order.is_empty():
		return manufacturing_order_summary(active_order)
	if production_status.has(index(tile)):
		return String(production_status[index(tile)])
	if get_building(tile) == Building.IMPORT_DEPOT:
		return import_summary()
	return "Idle"

func debug_summary() -> String:
	return "Money: %.1f  Workforce: %d/%d  Power spare: %.1f\nFood: %.1f  Materials: %.1f  Fuel: %.1f  Supplies: %.1f\n%s\n%s  %s" % [resources[LedgerResource.MONEY], employed_workforce, occupied_households, resources[LedgerResource.ELECTRICITY], resources[LedgerResource.FOOD], resources[LedgerResource.MATERIALS], resources[LedgerResource.FUEL], resources[LedgerResource.MILITARY_SUPPLIES], research_status, completed_technology_summary(), import_summary()]

func selection_summary(tile: Vector2i) -> String:
	var zone_type := get_zone(tile)
	var building_type := get_building(tile)
	var is_developed := building_type == Building.RESIDENTIAL or building_type == Building.COMMERCIAL
	if zone_type == Zone.NONE and not is_developed and building_definition(building_type).is_empty():
		var deposit: int = map_data.get_resource_deposit(tile)
		return "Deposit: %s" % deposit_name(deposit) if deposit != map_data.ResourceDeposit.NONE else ""
	if not building_definition(building_type).is_empty():
		return "%s\nStatus: %s" % [building_name(building_type), get_building_status(tile)]
	var road_status := "Connected" if has_road_access(tile) else "No access"
	var power_status := "Connected" if has_power(tile) else "No power"
	var water_status := "Connected" if has_water(tile) else "No water"
	var fire_status := "Covered" if has_fire_coverage(tile) else "Not covered"
	var summary := "Road: %s  Power: %s  Water: %s  Fire: %s" % [road_status, power_status, water_status, fire_status]
	if zone_type == Zone.RESIDENTIAL or building_type == Building.RESIDENTIAL:
		summary += "\nHouseholds: %d/%d" % [occupied_households, household_capacity]
	elif zone_type == Zone.COMMERCIAL or building_type == Building.COMMERCIAL:
		summary += "\nJobs: %d/%d" % [employed_workforce, job_capacity]
	return summary

func import_summary() -> String:
	if import_orders.is_empty():
		return "Import: %s selected" % resource_name(selected_import_resource)
	var order: Dictionary = import_orders[0]
	return "Import: %s %.0f ($%.0f) in %d tick(s)" % [resource_name(int(order["resource"])), float(order["quantity"]), float(order["cost"]), int(order["remaining"])]

func completed_technology_summary() -> String:
	var names: Array[String] = []
	for technology in range(Technology.INDUSTRIAL_EXPANSION, CityConfigScript.TECH_COUNT):
		if is_technology_unlocked(technology):
			names.append(technology_name(technology))
	return "Unlocked: %s" % (", ".join(names) if not names.is_empty() else "Developing City")

func manufacturing_order_at(tile: Vector2i) -> Dictionary:
	for entry in manufacturing_orders:
		var order: Dictionary = entry
		if order["tile"] == tile:
			return order
	return {}

func manufacturing_order_summary(order: Dictionary) -> String:
	var definition: Dictionary = unit_definition(int(order["unit"]))
	return "%s: %d tick(s) — $%.0f Mat %.0f Fuel %.0f Supplies %.0f" % [unit_name(int(order["unit"])), int(order["remaining"]), float(definition.get("money", 0.0)), float(definition.get("materials", 0.0)), float(definition.get("fuel", 0.0)), float(definition.get("supplies", 0.0))]

func has_service(coverage: PackedByteArray, tile: Vector2i) -> bool:
	if not map_data.is_valid(tile):
		return false
	if coverage[index(tile)] != 0:
		return true
	for direction in map_data.CARDINAL_DIRECTIONS:
		var road_tile: Vector2i = tile + direction
		if map_data.is_valid(road_tile) and coverage[index(road_tile)] != 0:
			return true
	return false

func has_required_deposit(tile: Vector2i, accepted_deposits: Array) -> bool:
	if accepted_deposits.has(map_data.get_resource_deposit(tile)):
		return true
	for direction in map_data.CARDINAL_DIRECTIONS:
		if accepted_deposits.has(map_data.get_resource_deposit(tile + direction)):
			return true
	return false

func remove_industry_building(tile: Vector2i) -> void:
	industry_buildings.erase(tile)
	production_status.erase(index(tile))

func remove_orders_at(tile: Vector2i) -> void:
	var remaining_orders: Array[Dictionary] = []
	for entry in manufacturing_orders:
		var order: Dictionary = entry
		if order["tile"] != tile:
			remaining_orders.append(order)
	manufacturing_orders = remaining_orders

func destroy_structure(tile: Vector2i) -> bool:
	if not map_data.is_valid(tile):
		return false
	var changed := false
	if get_building(tile) != Building.NONE:
		var previous := get_building(tile)
		buildings[index(tile)] = Building.NONE
		remove_industry_building(tile)
		remove_orders_at(tile)
		if previous == Building.POWER_PLANT or previous == Building.WATER_FACILITY or previous == Building.FIRE_STATION:
			network_dirty = true
		changed = true
	if has_road(tile):
		roads[index(tile)] = 0
		network_dirty = true
		changed = true
	if changed:
		rubble[index(tile)] = 1
	return changed

func utility_cost(building_type: int) -> float:
	match building_type:
		Building.POWER_PLANT: return CityConfigScript.POWER_PLANT_COST
		Building.WATER_FACILITY: return CityConfigScript.WATER_FACILITY_COST
		Building.FIRE_STATION: return CityConfigScript.FIRE_STATION_COST
		_: return 0.0

func utility_name(building_type: int) -> String:
	match building_type:
		Building.POWER_PLANT: return "Power plant"
		Building.WATER_FACILITY: return "Water facility"
		Building.FIRE_STATION: return "Fire station"
		_: return "Utility"

func building_definition(building_type: int) -> Dictionary:
	return CityConfigScript.BUILDING_DATA.get(building_type, {})

func technology_definition(technology: int) -> Dictionary:
	return CityConfigScript.TECHNOLOGY_DATA.get(technology, {})

func unit_definition(unit_type: int) -> Dictionary:
	return CityConfigScript.UNIT_DATA.get(unit_type, {})

func building_name(building_type: int) -> String:
	if building_type == Building.RESIDENTIAL:
		return "Residential"
	if building_type == Building.COMMERCIAL:
		return "Commercial"
	if building_type == Building.POWER_PLANT or building_type == Building.WATER_FACILITY or building_type == Building.FIRE_STATION:
		return utility_name(building_type)
	return String(building_definition(building_type).get("name", "Building"))

func technology_name(technology: int) -> String:
	return String(technology_definition(technology).get("name", "Technology"))

func unit_name(unit_type: int) -> String:
	return String(unit_definition(unit_type).get("name", "Unit"))

func resource_name(resource: int) -> String:
	match resource:
		LedgerResource.FOOD: return "Food"
		LedgerResource.MATERIALS: return "Materials"
		LedgerResource.FUEL: return "Fuel"
		LedgerResource.MILITARY_SUPPLIES: return "Military Supplies"
		LedgerResource.MONEY: return "Money"
		LedgerResource.ELECTRICITY: return "Electricity"
		_: return "Workforce"

func deposit_name(deposit: int) -> String:
	match deposit:
		map_data.ResourceDeposit.IRON: return "Iron"
		map_data.ResourceDeposit.STONE: return "Stone"
		map_data.ResourceDeposit.OIL: return "Oil"
		_: return "None"

func reject_action(reason: String) -> bool:
	last_action_reason = reason
	return false

func accept_action(message: String) -> bool:
	last_action_reason = message
	return true
