extends SceneTree

const MapDataScript = preload("res://scripts/map_data.gd")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CityConfigScript = preload("res://scripts/city_config.gd")
const MainScene = preload("res://scenes/main.tscn")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run_validation")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run_validation() -> void:
	validate_deposits_and_placement()
	validate_production()
	validate_imports()
	validate_research()
	validate_manufacturing()
	validate_economy_safety()
	validate_main_industry_input()
	if failures.is_empty():
		print("Industry validation passed: production, imports, research, manufacturing, and economy safety.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func validate_deposits_and_placement() -> void:
	var first = MapDataScript.new()
	var second = MapDataScript.new()
	var solid_deposit := find_deposit(first, [MapDataScript.ResourceDeposit.IRON, MapDataScript.ResourceDeposit.STONE])
	expect(solid_deposit == find_deposit(second, [MapDataScript.ResourceDeposit.IRON, MapDataScript.ResourceDeposit.STONE]), "Same seed must keep the same solid deposit relationship")
	var city = CitySimulationScript.new(first)
	city.completed_technologies[CitySimulationScript.Technology.INDUSTRIAL_EXPANSION] = 1
	var ordinary_land := find_non_deposit_land(first)
	expect(not city.place_industry_building(ordinary_land, CitySimulationScript.Building.MATERIALS_PLANT), "Materials Plant must reject a missing solid deposit")
	expect(city.last_action_reason == "Cannot build: Missing resource deposit", "Missing-deposit feedback is incorrect")
	expect(city.place_industry_building(solid_deposit, CitySimulationScript.Building.MATERIALS_PLANT), "Materials Plant should place on a deterministic solid deposit")
	var locked_city = CitySimulationScript.new(MapDataScript.new())
	expect(not locked_city.place_industry_building(find_non_deposit_land(locked_city.map_data), CitySimulationScript.Building.MATERIALS_PLANT), "Locked industrial building should reject placement")
	expect(locked_city.last_action_reason == "Cannot build: Technology not researched", "Locked-building feedback is incorrect")

func validate_production() -> void:
	var city = make_operational_city()
	var farm := find_unoccupied_land(city)
	add_industry_building(city, farm, CitySimulationScript.Building.FARM)
	var materials := find_unoccupied_deposit(city, [MapDataScript.ResourceDeposit.IRON, MapDataScript.ResourceDeposit.STONE])
	add_industry_building(city, materials, CitySimulationScript.Building.MATERIALS_PLANT)
	var refinery := find_unoccupied_deposit(city, [MapDataScript.ResourceDeposit.OIL])
	add_industry_building(city, refinery, CitySimulationScript.Building.REFINERY)
	var defense := find_unoccupied_land(city)
	add_industry_building(city, defense, CitySimulationScript.Building.DEFENSE_FACTORY)
	var food_before := city.get_resource(CitySimulationScript.LedgerResource.FOOD)
	var materials_before := city.get_resource(CitySimulationScript.LedgerResource.MATERIALS)
	var fuel_before := city.get_resource(CitySimulationScript.LedgerResource.FUEL)
	var supplies_before := city.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES)
	city.tick()
	expect(city.get_resource(CitySimulationScript.LedgerResource.FOOD) > food_before, "Farm must produce Food")
	expect(city.get_resource(CitySimulationScript.LedgerResource.MATERIALS) > materials_before, "Materials Plant must produce Materials")
	expect(city.get_resource(CitySimulationScript.LedgerResource.FUEL) > fuel_before, "Refinery must produce Fuel")
	expect(city.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES) > supplies_before, "Defense Factory must produce Military Supplies")

	var unstaffed = make_unstaffed_city()
	var unstaffed_farm := find_unoccupied_land(unstaffed)
	add_industry_building(unstaffed, unstaffed_farm, CitySimulationScript.Building.FARM)
	var unstaffed_food := unstaffed.get_resource(CitySimulationScript.LedgerResource.FOOD)
	unstaffed.tick()
	expect(is_equal_approx(unstaffed.get_resource(CitySimulationScript.LedgerResource.FOOD), unstaffed_food), "Missing workforce must stop production")
	expect(unstaffed.get_building_status(unstaffed_farm) == "Not enough workers", "Missing-workforce feedback is incorrect")

	var powerless = make_operational_city(false)
	var powerless_farm := find_unoccupied_land(powerless)
	add_industry_building(powerless, powerless_farm, CitySimulationScript.Building.FARM)
	var powerless_food := powerless.get_resource(CitySimulationScript.LedgerResource.FOOD)
	powerless.tick()
	expect(is_equal_approx(powerless.get_resource(CitySimulationScript.LedgerResource.FOOD), powerless_food - powerless.occupied_households * 0.05), "Missing electricity must stop farm output")
	expect(powerless.get_building_status(powerless_farm) == "No available electricity", "Missing-electricity feedback is incorrect")
	var disconnected = make_operational_city()
	disconnected.power_coverage.fill(0)
	var disconnected_farm := find_unoccupied_land(disconnected)
	add_industry_building(disconnected, disconnected_farm, CitySimulationScript.Building.FARM)
	disconnected.tick()
	expect(disconnected.get_building_status(disconnected_farm) == "No power", "Missing power coverage must stop production")
	var no_road = make_operational_city()
	no_road.roads.fill(0)
	var no_road_farm := find_unoccupied_land(no_road)
	add_industry_building(no_road, no_road_farm, CitySimulationScript.Building.FARM)
	no_road.tick()
	expect(no_road.get_building_status(no_road_farm) == "No road access", "Missing road access must stop production")

	var stalled = make_operational_city()
	var stalled_factory := find_unoccupied_land(stalled)
	add_industry_building(stalled, stalled_factory, CitySimulationScript.Building.DEFENSE_FACTORY)
	stalled.resources[CitySimulationScript.LedgerResource.MATERIALS] = 0.0
	stalled.tick()
	expect(stalled.get_building_status(stalled_factory) == "Not enough Materials", "Missing-input feedback is incorrect")
	stalled.resources[CitySimulationScript.LedgerResource.MATERIALS] = 2.0
	var resumed_supplies := stalled.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES)
	stalled.tick()
	expect(stalled.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES) > resumed_supplies, "Production should resume once inputs return")

func validate_imports() -> void:
	var city = make_operational_city()
	var depot := find_unoccupied_land(city)
	add_industry_building(city, depot, CitySimulationScript.Building.IMPORT_DEPOT)
	city.resources[CitySimulationScript.LedgerResource.MATERIALS] = 0.0
	var money_before := city.get_resource(CitySimulationScript.LedgerResource.MONEY)
	var expected_cost: float = CityConfigScript.IMPORT_PRICES[CitySimulationScript.LedgerResource.MATERIALS] * CityConfigScript.IMPORT_QUANTITY
	expect(city.place_import_order(CitySimulationScript.LedgerResource.MATERIALS), "Import order should succeed with an operational depot")
	expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MONEY), money_before - expected_cost), "Import order deducted an incorrect cost")
	expect(city.import_orders.size() == 1 and int(city.import_orders[0]["remaining"]) == CityConfigScript.IMPORT_DELAY_TICKS, "Import order must retain deterministic delay state")
	for tick in range(CityConfigScript.IMPORT_DELAY_TICKS - 1):
		city.tick()
		expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MATERIALS), 0.0), "Import resource arrived before completion")
	city.tick()
	expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MATERIALS), CityConfigScript.IMPORT_QUANTITY), "Import resource must arrive exactly once after its delay")
	expect(city.import_orders.is_empty(), "Completed import order must be removed")
	city.resources[CitySimulationScript.LedgerResource.MONEY] = 0.0
	var failed_money := city.get_resource(CitySimulationScript.LedgerResource.MONEY)
	expect(not city.place_import_order(CitySimulationScript.LedgerResource.FUEL), "Insufficient-money import should fail")
	expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MONEY), failed_money), "Failed import must not deduct money")
	expect(city.last_action_reason == "Cannot import: Not enough money", "Insufficient-money import feedback is incorrect")
	var selected: int = city.selected_import_resource
	city.cycle_import_resource()
	expect(city.selected_import_resource != selected, "Import resource selection should cycle deterministically")

func validate_research() -> void:
	var city = make_operational_city()
	var university := find_unoccupied_land(city)
	add_industry_building(city, university, CitySimulationScript.Building.UNIVERSITY)
	expect(city.start_research(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION), "Research should start with an operational University")
	expect(not city.start_research(CitySimulationScript.Technology.REFINING), "Only one technology may be active at a time")
	for tick in range(3):
		city.tick()
	expect(city.is_technology_unlocked(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION), "Completed research must unlock its technology")
	expect(city.active_technology == CitySimulationScript.Technology.NONE, "Completed research must clear the active technology")

	var one_lab = make_operational_city()
	add_industry_building(one_lab, find_unoccupied_land(one_lab), CitySimulationScript.Building.UNIVERSITY)
	expect(one_lab.start_research(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION), "Single-lab research setup failed")
	one_lab.tick()
	var one_progress: float = one_lab.research_progress
	var two_labs = make_operational_city()
	add_industry_building(two_labs, find_unoccupied_land(two_labs), CitySimulationScript.Building.UNIVERSITY)
	add_industry_building(two_labs, find_unoccupied_land(two_labs), CitySimulationScript.Building.RESEARCH_LAB)
	expect(two_labs.start_research(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION), "Two-lab research setup failed")
	two_labs.tick()
	expect(two_labs.research_progress > one_progress and two_labs.research_progress < one_progress * 2.0, "Additional labs must apply diminishing research returns")

func validate_manufacturing() -> void:
	var no_facility = make_operational_city()
	expect(not no_facility.queue_unit(find_unoccupied_land(no_facility), CitySimulationScript.UnitType.TANK), "Manufacturing must require the correct facility")
	expect(no_facility.last_action_reason.contains("Requires Vehicle Factory"), "Missing-facility feedback is incorrect")
	var no_technology = make_operational_city()
	var vehicle := find_unoccupied_land(no_technology)
	add_industry_building(no_technology, vehicle, CitySimulationScript.Building.VEHICLE_FACTORY)
	expect(not no_technology.queue_unit(vehicle, CitySimulationScript.UnitType.TANK), "Locked unit should reject manufacturing")
	expect(no_technology.last_action_reason == "Cannot manufacture: Technology not researched", "Missing-technology feedback is incorrect")
	var insufficient_resources = make_operational_city()
	var barracks := find_unoccupied_land(insufficient_resources)
	add_industry_building(insufficient_resources, barracks, CitySimulationScript.Building.BARRACKS)
	insufficient_resources.resources[CitySimulationScript.LedgerResource.MILITARY_SUPPLIES] = 0.0
	var failed_money := insufficient_resources.get_resource(CitySimulationScript.LedgerResource.MONEY)
	expect(not insufficient_resources.queue_unit(barracks, CitySimulationScript.UnitType.INFANTRY), "Missing manufacturing inputs should reject the order")
	expect(insufficient_resources.last_action_reason == "Cannot manufacture: Not enough military supplies", "Missing-resource manufacturing feedback is incorrect")
	expect(is_equal_approx(insufficient_resources.get_resource(CitySimulationScript.LedgerResource.MONEY), failed_money), "Failed manufacturing must not partially deduct resources")

	for unit_type in range(CitySimulationScript.UnitType.INFANTRY, CityConfigScript.UNIT_COUNT):
		var city = make_operational_city()
		var unit_data: Dictionary = city.unit_definition(unit_type)
		var facility: int = int(unit_data["facility"])
		var facility_tile := find_unoccupied_land(city)
		add_industry_building(city, facility_tile, facility)
		var technology: int = int(unit_data.get("tech", CitySimulationScript.Technology.NONE))
		if technology != CitySimulationScript.Technology.NONE:
			city.completed_technologies[technology] = 1
		city.resources[CitySimulationScript.LedgerResource.MONEY] = 1000.0
		city.resources[CitySimulationScript.LedgerResource.MATERIALS] = 100.0
		city.resources[CitySimulationScript.LedgerResource.FUEL] = 100.0
		city.resources[CitySimulationScript.LedgerResource.MILITARY_SUPPLIES] = 100.0
		var money_before := city.get_resource(CitySimulationScript.LedgerResource.MONEY)
		var materials_before := city.get_resource(CitySimulationScript.LedgerResource.MATERIALS)
		var fuel_before := city.get_resource(CitySimulationScript.LedgerResource.FUEL)
		var supplies_before := city.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES)
		var tax_collected := 0.0
		expect(city.queue_unit(facility_tile, unit_type), "%s queue should succeed with valid prerequisites" % city.unit_name(unit_type))
		expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MONEY), money_before), "Queued manufacturing must not deduct before completion")
		for tick in range(int(unit_data["ticks"]) - 1):
			city.tick()
			tax_collected += city.occupied_households * CityConfigScript.TAX_PER_OCCUPIED_HOUSEHOLD
			expect(city.get_produced_unit_count(unit_type) == 0, "%s completed too early" % city.unit_name(unit_type))
		city.tick()
		tax_collected += city.occupied_households * CityConfigScript.TAX_PER_OCCUPIED_HOUSEHOLD
		expect(city.get_produced_unit_count(unit_type) == 1, "%s must enter produced-unit inventory exactly once" % city.unit_name(unit_type))
		expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MONEY), money_before - float(unit_data["money"]) + tax_collected), "%s deducted incorrect money" % city.unit_name(unit_type))
		expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MATERIALS), materials_before - float(unit_data["materials"])), "%s deducted incorrect materials" % city.unit_name(unit_type))
		expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.FUEL), fuel_before - float(unit_data["fuel"])), "%s deducted incorrect fuel" % city.unit_name(unit_type))
		expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES), supplies_before - float(unit_data["supplies"])), "%s deducted incorrect military supplies" % city.unit_name(unit_type))

func validate_economy_safety() -> void:
	var city = make_operational_city()
	var factory := find_unoccupied_land(city)
	add_industry_building(city, factory, CitySimulationScript.Building.DEFENSE_FACTORY)
	city.resources[CitySimulationScript.LedgerResource.MATERIALS] = 0.0
	for tick in range(5):
		city.tick()
	for resource in city.resources:
		expect(is_finite(resource) and resource >= 0.0, "Industry ledger must not contain invalid or negative values")
	expect(city.employed_workforce <= city.occupied_households, "Industry workforce allocation must remain bounded")
	expect(is_finite(city.get_resource(CitySimulationScript.LedgerResource.ELECTRICITY)) and city.get_resource(CitySimulationScript.LedgerResource.ELECTRICITY) >= 0.0, "Electricity must remain capacity-safe")

func validate_main_industry_input() -> void:
	var main = MainScene.instantiate()
	get_root().add_child(main)
	main.selected_tile = find_unoccupied_land(main.city)
	var farm_key := InputEventKey.new()
	farm_key.pressed = true
	farm_key.keycode = KEY_F
	main._unhandled_input(farm_key)
	expect(main.city.get_building(main.selected_tile) == CitySimulationScript.Building.FARM, "Main input path must place a Farm")
	main.selected_tile = find_unoccupied_land(main.city)
	var materials_key := InputEventKey.new()
	materials_key.pressed = true
	materials_key.keycode = KEY_M
	main._unhandled_input(materials_key)
	expect(main.city.last_action_reason == "Cannot build: Technology not researched", "Main input path must expose locked-building feedback")
	main.update_debug_overlay(0.016)
	expect(main.overlay.label.text.contains("Technology not researched"), "Overlay should display Industry construction feedback")
	main.queue_free()

func make_operational_city(include_power: bool = true) -> CitySimulation:
	var city = CitySimulationScript.new(MapDataScript.new())
	city.roads.fill(1)
	city.power_coverage.fill(1)
	city.water_coverage.fill(1)
	city.fire_coverage.fill(1)
	city.network_dirty = false
	city.resources[CitySimulationScript.LedgerResource.MONEY] = 10000.0
	city.resources[CitySimulationScript.LedgerResource.MATERIALS] = 100.0
	city.resources[CitySimulationScript.LedgerResource.FUEL] = 100.0
	city.resources[CitySimulationScript.LedgerResource.MILITARY_SUPPLIES] = 100.0
	var residences := 0
	for y in city.map_data.size.y:
		for x in city.map_data.size.x:
			var tile := Vector2i(x, y)
			if city.map_data.is_land(tile) and residences < 13:
				city.buildings[city.index(tile)] = CitySimulationScript.Building.RESIDENTIAL
				residences += 1
		if residences >= 13:
			break
	city.occupied_households = 10
	if include_power:
		city.buildings[city.index(find_unoccupied_land(city))] = CitySimulationScript.Building.POWER_PLANT
	city.resources[CitySimulationScript.LedgerResource.ELECTRICITY] = CityConfigScript.POWER_CAPACITY
	return city

func make_unstaffed_city() -> CitySimulation:
	var city = CitySimulationScript.new(MapDataScript.new())
	city.roads.fill(1)
	city.power_coverage.fill(1)
	city.water_coverage.fill(1)
	city.fire_coverage.fill(1)
	city.network_dirty = false
	city.resources[CitySimulationScript.LedgerResource.MONEY] = 10000.0
	city.buildings[city.index(find_unoccupied_land(city))] = CitySimulationScript.Building.POWER_PLANT
	return city

func add_industry_building(city, tile: Vector2i, building_type: int) -> void:
	city.buildings[city.index(tile)] = building_type
	city.industry_buildings.append(tile)

func find_unoccupied_land(city) -> Vector2i:
	for y in city.map_data.size.y:
		for x in city.map_data.size.x:
			var tile := Vector2i(x, y)
			if city.map_data.is_land(tile) and city.get_building(tile) == CitySimulationScript.Building.NONE:
				return tile
	return Vector2i(-1, -1)

func find_non_deposit_land(data) -> Vector2i:
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x, y)
			if data.is_land(tile) and not data.has_resource_deposit(tile) and not data.is_capital_marker(tile):
				return tile
	return Vector2i(-1, -1)

func find_deposit(data, accepted: Array) -> Vector2i:
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x, y)
			if accepted.has(data.get_resource_deposit(tile)):
				return tile
	return Vector2i(-1, -1)

func find_unoccupied_deposit(city, accepted: Array) -> Vector2i:
	for y in city.map_data.size.y:
		for x in city.map_data.size.x:
			var tile := Vector2i(x, y)
			if city.get_building(tile) == CitySimulationScript.Building.NONE and accepted.has(city.map_data.get_resource_deposit(tile)):
				return tile
	return Vector2i(-1, -1)
