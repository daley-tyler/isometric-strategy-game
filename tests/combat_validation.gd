extends SceneTree

const MapDataScript = preload("res://scripts/map_data.gd")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CombatSimulationScript = preload("res://scripts/combat_simulation.gd")
const CombatConfigScript = preload("res://scripts/combat_config.gd")

var failures: Array[String] = []

func _init() -> void: call_deferred("run_validation")
func expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func run_validation() -> void:
	validate_deployment_selection_and_commands()
	validate_movement_and_paths()
	validate_damage_defense_and_death()
	validate_territory_capitals_and_ai()
	if failures.is_empty():
		print("Combat validation passed: deployment, orders, pathing, damage, territory, capitals, and AI.")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func make_combat() -> Dictionary:
	var data = MapDataScript.new()
	var city = CitySimulationScript.new(data)
	return {"data": data, "city": city, "combat": CombatSimulationScript.new(data, city)}

func validate_deployment_selection_and_commands() -> void:
	var setup := make_combat(); var data = setup.data; var city = setup.city; var combat = setup.combat
	city.produced_units[CitySimulationScript.UnitType.INFANTRY] = 2
	var before: int = city.get_produced_unit_count(CitySimulationScript.UnitType.INFANTRY)
	expect(combat.deploy_produced_unit(CitySimulationScript.UnitType.INFANTRY, data.player_capital), "Capital-area deployment should succeed")
	expect(city.get_produced_unit_count(CitySimulationScript.UnitType.INFANTRY) == before - 1 and combat.units.size() == 1, "Deployment must consume exactly one inventory item and create one unit")
	expect(not combat.deploy_produced_unit(CitySimulationScript.UnitType.TANK, data.player_capital), "Missing manufactured unit must reject deployment")
	var unit_id: int = combat.unit_at(data.player_capital, CombatConfigScript.OWNER_PLAYER)
	expect(combat.select_unit_at(data.player_capital) and combat.selected_unit_id == unit_id, "Player unit selection must work")
	expect(combat.issue_defend(unit_id) and int(combat.get_unit(unit_id)["command"]) == CombatConfigScript.COMMAND_DEFEND, "Defend command must apply")
	expect(combat.issue_stop(unit_id) and int(combat.get_unit(unit_id)["command"]) == CombatConfigScript.COMMAND_STOP, "Stop command must apply")
	combat.clear_selection(); expect(combat.selected_unit_id < 0, "Selection must clear safely")
	var second: int = combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.INFANTRY, data.player_capital + Vector2i(1, 0))
	expect(second > unit_id, "Unit ids must be deterministic and unique")

func validate_movement_and_paths() -> void:
	var setup := make_combat(); var data = setup.data; var combat = setup.combat
	var ground_tile: Vector2i = data.player_capital
	var ground: int = combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.INFANTRY, ground_tile)
	var destination := nearest_ground(data, ground_tile + Vector2i(4, 0))
	var path_a: Array[Vector2i] = combat.find_path(ground_tile, destination, false); var path_b: Array[Vector2i] = combat.find_path(ground_tile, destination, false)
	expect(path_a == path_b and path_a.size() > 1, "Identical ground orders must produce identical cached paths")
	var rebuilds: int = combat.path_rebuild_count
	expect(combat.issue_move(ground, destination), "Ground Move order should succeed")
	for tick in 8: combat.tick()
	expect(combat.path_rebuild_count == rebuilds + 1, "Path must not recalculate during ordinary movement")
	expect(not combat.issue_move(ground, find_terrain(data, MapDataScript.Terrain.COAST)), "Ground movement must reject coast/water")
	var river := find_terrain(data, MapDataScript.Terrain.RIVER)
	expect(combat.find_path(ground_tile, river, false).is_empty(), "Ground path must reject an unbridged river destination")
	var bridge := find_bridge(data)
	expect(not combat.find_path(ground_tile, bridge, false).is_empty(), "Ground path must use a deterministic bridge crossing")
	var aircraft: int = combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.RECON_DRONE, ground_tile)
	expect(combat.issue_move(aircraft, find_terrain(data, MapDataScript.Terrain.COAST)), "Aircraft must be able to cross water")
	expect(combat.issue_stop(aircraft), "Stop must cancel aircraft movement")
	var slow_tile := find_terrain(data, MapDataScript.Terrain.FOREST)
	var slow_start := nearest_ground(data, slow_tile + Vector2i(-1, 0))
	var slow_unit: int = combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.INFANTRY, slow_start)
	if slow_start.distance_squared_to(slow_tile) == 1 and combat.issue_move(slow_unit, slow_tile):
		combat.tick()
		expect(int(combat.get_unit(slow_unit)["move_wait"]) == 1, "Forest movement must apply its deterministic slowdown")

func validate_damage_defense_and_death() -> void:
	var setup := make_combat(); var data = setup.data; var combat = setup.combat
	var plain := nearest_ground(data, data.player_capital)
	var attacker: int = combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.TANK, plain)
	var defender: int = combat.spawn_developer_unit(CombatConfigScript.OWNER_AI, CitySimulationScript.UnitType.INFANTRY, nearest_ground(data, plain + Vector2i(1, 0)))
	expect(not combat.issue_attack(attacker, attacker), "Friendly targeting must be rejected")
	var health_before: float = float(combat.get_unit(defender)["health"])
	expect(combat.issue_attack(attacker, defender), "Enemy target must be accepted")
	combat.tick(); expect(float(combat.get_unit(defender)["health"]) < health_before, "Armor-adjusted damage must reduce health")
	combat.get_unit(defender)["health"] = 1.0; combat.apply_attack(attacker, defender)
	expect(not bool(combat.get_unit(defender)["alive"]), "Dead units must be marked exactly once")
	combat.select_unit_at(Vector2i(combat.get_unit(defender)["tile"]), CombatConfigScript.OWNER_AI)
	expect(combat.selected_unit_id < 0, "Dead selected units must not leave invalid selection references")
	expect(not combat.issue_move(defender, plain), "Dead units cannot move")
	expect(not combat.issue_attack(attacker, defender), "Dead units cannot remain valid targets")
	expect(is_finite(float(combat.get_unit(attacker)["health"])), "Combat state must remain finite")
	var forest_setup := make_combat(); var forest_data = forest_setup.data; var forest_combat = forest_setup.combat
	var forest := find_terrain(forest_data, MapDataScript.Terrain.FOREST)
	var forest_attacker: int = forest_combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.INFANTRY, forest)
	var forest_defender: int = forest_combat.spawn_developer_unit(CombatConfigScript.OWNER_AI, CitySimulationScript.UnitType.INFANTRY, forest)
	var forest_health: float = float(forest_combat.get_unit(forest_defender)["health"])
	forest_combat.apply_attack(forest_attacker, forest_defender)
	expect(float(forest_combat.get_unit(forest_defender)["health"]) > forest_health - 6.0, "Forest defense bonus must apply deterministically")

func validate_territory_capitals_and_ai() -> void:
	var setup := make_combat(); var data = setup.data; var combat = setup.combat
	var infantry: int = combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.INFANTRY, data.ai_capital)
	for tick in CombatConfigScript.CAPITAL_CAPTURE_TICKS: combat.tick()
	expect(combat.ai_capital_owner == CombatConfigScript.OWNER_PLAYER and combat.status_message == "AI CAPITAL CAPTURED", "Player must deterministically capture AI capital")
	expect(combat.territory[data.index(data.ai_capital)] == CombatConfigScript.OWNER_PLAYER, "Ground unit must capture authoritative territory")
	var aircraft_setup := make_combat(); var air_combat = aircraft_setup.combat; var air_data = aircraft_setup.data
	var drone: int = air_combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.RECON_DRONE, air_data.player_capital)
	for tick in 3: air_combat.tick()
	expect(air_combat.territory[air_data.index(air_data.player_capital)] == CombatConfigScript.OWNER_NEUTRAL, "Aircraft must not capture territory")
	var ai_setup := make_combat(); var ai_combat = ai_setup.combat; var ai_data = ai_setup.data
	expect(ai_combat.spawn_developer_ai_force(), "Developer AI setup should spawn once")
	ai_combat.tick()
	var ai_id: int = ai_combat.unit_at(ai_data.ai_capital, CombatConfigScript.OWNER_AI)
	expect(ai_id >= 0 and int(ai_combat.get_unit(ai_id)["command"]) == CombatConfigScript.COMMAND_MOVE, "AI must use a valid movement order toward the player capital")
	var nearby_player: int = ai_combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.INFANTRY, ai_data.ai_capital + Vector2i(1, 0))
	ai_combat.tick()
	expect(int(ai_combat.get_unit(ai_id)["command"]) == CombatConfigScript.COMMAND_ATTACK, "AI must attack nearby valid player forces")
	var player_setup := make_combat(); var player_combat = player_setup.combat; var player_data = player_setup.data
	player_combat.spawn_developer_unit(CombatConfigScript.OWNER_AI, CitySimulationScript.UnitType.INFANTRY, player_data.player_capital)
	for tick in CombatConfigScript.CAPITAL_CAPTURE_TICKS: player_combat.tick()
	expect(player_combat.player_capital_owner == CombatConfigScript.OWNER_AI, "AI must be able to capture player capital")

func nearest_ground(data, preferred: Vector2i) -> Vector2i:
	for radius in range(data.size.x):
		for y in range(preferred.y - radius, preferred.y + radius + 1):
			for x in range(preferred.x - radius, preferred.x + radius + 1):
				var tile := Vector2i(x, y)
				if data.is_traversable_ground(tile): return tile
	return Vector2i(-1, -1)

func find_terrain(data, terrain: int) -> Vector2i:
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x, y)
			if data.get_terrain(tile) == terrain: return tile
	return Vector2i(-1, -1)

func find_bridge(data) -> Vector2i:
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x, y)
			if data.is_bridge(tile): return tile
	return Vector2i(-1, -1)
