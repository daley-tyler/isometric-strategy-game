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
	validate_research_graph()
	validate_university_progression()
	validate_research_determinism()
	await validate_building_presentation()
	if failures.is_empty():
		print("Progression validation passed: research reachability, facility handoff, and building presentation.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func validate_research_graph() -> void:
	var data = MapDataScript.new()
	var city = CitySimulationScript.new(data)
	var technology_count := CityConfigScript.TECH_COUNT
	for technology in range(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION, technology_count):
		var visited := {}
		var current := technology
		while current != CitySimulationScript.Technology.NONE:
			expect(not visited.has(current), "Technology prerequisite cycle includes %d" % technology)
			if visited.has(current):
				break
			visited[current] = true
			var definition: Dictionary = city.technology_definition(current)
			var prerequisite := int(definition.get("prerequisite", CitySimulationScript.Technology.NONE))
			expect(prerequisite >= CitySimulationScript.Technology.NONE and prerequisite < technology_count, "Technology %d has an invalid prerequisite" % current)
			current = prerequisite

	for building_key in CityConfigScript.BUILDING_DATA.keys():
		var building_type := int(building_key)
		var unlock := int(city.building_definition(building_type).get("unlock", CitySimulationScript.Technology.NONE))
		expect(unlock >= CitySimulationScript.Technology.NONE and unlock < technology_count, "Building %d has an invalid unlock technology" % building_type)
		expect(reachable_technology(city, unlock), "Building %d has no reachable unlock chain" % building_type)
	for unit_key in CityConfigScript.UNIT_DATA.keys():
		var unit_type := int(unit_key)
		var unlock := int(city.unit_definition(unit_type).get("tech", CitySimulationScript.Technology.NONE))
		expect(unlock >= CitySimulationScript.Technology.NONE and unlock < technology_count, "Unit %d has an invalid technology" % unit_type)
		expect(reachable_technology(city, unlock), "Unit %d has no reachable technology chain" % unit_type)

func reachable_technology(city, technology: int) -> bool:
	var visited := {}
	var current := technology
	while current != CitySimulationScript.Technology.NONE:
		if visited.has(current):
			return false
		visited[current] = true
		current = int(city.technology_definition(current).get("prerequisite", CitySimulationScript.Technology.NONE))
	return true

func validate_university_progression() -> void:
	var city = make_research_city()
	expect(city.start_next_research(), "A staffed University must have an available first technology")
	expect(city.active_technology == CitySimulationScript.Technology.INDUSTRIAL_EXPANSION, "University should start Industrial Expansion first")
	for tick in range(3):
		city.tick()
	expect(city.is_technology_unlocked(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION), "University-only research did not complete Industrial Expansion")
	var lab_tile := find_open_land(city)
	expect(city.place_industry_building(lab_tile, CitySimulationScript.Building.RESEARCH_LAB), "Industrial Expansion must unlock Research Laboratory placement")
	expect(city.get_building(lab_tile) == CitySimulationScript.Building.RESEARCH_LAB, "Research Laboratory placement state is missing")
	connect_road(city, lab_tile)

	var university_only = make_research_city()
	for technology in [CitySimulationScript.Technology.INDUSTRIAL_EXPANSION, CitySimulationScript.Technology.REFINING, CitySimulationScript.Technology.DEFENSE_INDUSTRY]:
		university_only.completed_technologies[technology] = 1
	expect(not university_only.start_next_research(), "Advanced research must not bypass its Laboratory requirement")
	expect(university_only.last_action_reason == "Cannot research: Requires Research Laboratory", "Laboratory requirement feedback is unclear")
	var lab := find_open_land(university_only)
	add_building(university_only, lab, CitySimulationScript.Building.RESEARCH_LAB, true)
	expect(university_only.start_next_research(), "Research Laboratory should open the advanced research path")
	expect(university_only.active_technology == CitySimulationScript.Technology.ADVANCED_MANUFACTURING, "Advanced Manufacturing should follow the early University branch")

	var no_facility = CitySimulationScript.new(MapDataScript.new())
	expect(not no_facility.start_next_research(), "Research without a facility should be rejected")
	expect(no_facility.last_action_reason.contains("Requires University"), "No-facility research feedback should identify the missing facility")
	for technology in range(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION, CityConfigScript.TECH_COUNT):
		no_facility.completed_technologies[technology] = 1
	expect(not no_facility.start_next_research() and no_facility.last_action_reason == "Cannot research: All technologies completed", "Completed research should remain safely terminal")

func validate_research_determinism() -> void:
	var first = make_research_city()
	var second = make_research_city()
	for step in range(12):
		if first.active_technology == CitySimulationScript.Technology.NONE:
			first.start_next_research()
		if second.active_technology == CitySimulationScript.Technology.NONE:
			second.start_next_research()
		first.tick()
		second.tick()
	expect(first.completed_technologies == second.completed_technologies, "Research completion must be deterministic")
	expect(first.active_technology == second.active_technology and is_equal_approx(first.research_progress, second.research_progress), "Research progress must be deterministic")

func validate_building_presentation() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	expect(main.world_renderer.chunks.size() == 64, "World renderer must retain 64 cached chunks")
	for chunk in main.world_renderer.chunks:
		expect(chunk.building_overlay != null, "Each chunk must have one cached building overlay")
	var occupied: Array[Vector2i] = []
	for building_type in range(CitySimulationScript.Building.POWER_PLANT, CitySimulationScript.Building.MISSILE_SILO + 1):
		var tile := find_main_open_land(main, occupied)
		if tile.x < 0:
			continue
		occupied.append(tile)
		main.city.buildings[main.city.index(tile)] = building_type
		main.world_renderer.refresh_tile(tile)
	await process_frame
	expect(occupied.size() == CitySimulationScript.Building.MISSILE_SILO, "Presentation test should cover every prototype building silhouette")
	main.queue_free()

func make_research_city() -> CitySimulation:
	var city = CitySimulationScript.new(MapDataScript.new())
	city.resources[CitySimulationScript.LedgerResource.MONEY] = 10000.0
	city.resources[CitySimulationScript.LedgerResource.MATERIALS] = 100.0
	city.power_coverage.fill(1)
	city.water_coverage.fill(1)
	city.fire_coverage.fill(1)
	city.network_dirty = false
	for index in range(10):
		add_building(city, find_open_land(city), CitySimulationScript.Building.RESIDENTIAL, false)
	add_building(city, find_open_land(city), CitySimulationScript.Building.POWER_PLANT, false)
	var university := find_open_land(city)
	add_building(city, university, CitySimulationScript.Building.UNIVERSITY, true)
	city.recalculate_totals()
	return city

func add_building(city, tile: Vector2i, building_type: int, add_to_industry: bool) -> void:
	city.buildings[city.index(tile)] = building_type
	if add_to_industry:
		city.industry_buildings.append(tile)
	connect_road(city, tile)

func connect_road(city, tile: Vector2i) -> void:
	for direction in city.map_data.CARDINAL_DIRECTIONS:
		var road_tile: Vector2i = tile + direction
		if city.map_data.is_valid(road_tile) and city.map_data.is_land(road_tile) and city.get_building(road_tile) == CitySimulationScript.Building.NONE:
			city.roads[city.index(road_tile)] = 1

func find_open_land(city) -> Vector2i:
	for y in city.map_data.size.y:
		for x in city.map_data.size.x:
			var tile := Vector2i(x, y)
			if city.map_data.is_land(tile) and city.get_building(tile) == CitySimulationScript.Building.NONE and not city.has_road(tile):
				return tile
	return Vector2i(-1, -1)

func find_main_open_land(main, occupied: Array[Vector2i]) -> Vector2i:
	for y in main.map_data.size.y:
		for x in main.map_data.size.x:
			var tile := Vector2i(x, y)
			if main.map_data.is_land(tile) and main.city.get_building(tile) == CitySimulationScript.Building.NONE and not occupied.has(tile):
				return tile
	return Vector2i(-1, -1)
