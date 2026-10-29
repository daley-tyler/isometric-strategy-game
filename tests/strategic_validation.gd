extends SceneTree

const MapDataScript = preload("res://scripts/map_data.gd")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CombatSimulationScript = preload("res://scripts/combat_simulation.gd")
const CombatConfigScript = preload("res://scripts/combat_config.gd")
const StrategicSimulationScript = preload("res://scripts/strategic_simulation.gd")
const StrategicConfigScript = preload("res://scripts/strategic_config.gd")
const CombatRendererScript = preload("res://scripts/combat_renderer.gd")
const IsoMathScript = preload("res://scripts/iso_math.gd")

var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	if not value: failures.append(message)
func run() -> void:
	artillery_tests(); missile_tests(); presentation_tests(); sam_and_rubble_tests()
	if failures.is_empty(): print("Strategic validation passed: artillery, missiles, SAMs, damage, and rubble."); quit(0)
	else: for failure in failures: push_error(failure); quit(1)
func setup() -> Dictionary:
	var map = MapDataScript.new(); var city = CitySimulationScript.new(map); var combat = CombatSimulationScript.new(map, city)
	return {"map": map, "city": city, "combat": combat, "strategic": StrategicSimulationScript.new(map, city, combat)}
func artillery_tests() -> void:
	var s := setup(); var map = s.map; var combat = s.combat; var origin: Vector2i = map.player_capital
	var artillery: int = combat.spawn_developer_unit(1, 3, origin)
	expect(not combat.issue_artillery_strike(artillery, origin + Vector2i(1, 0)), "Artillery must reject minimum range")
	expect(not combat.issue_artillery_strike(artillery, origin + Vector2i(6, 0)), "Artillery must reject maximum range")
	var target := origin + Vector2i(2, 0); var enemy: int = combat.spawn_developer_unit(2, 1, target); var friend: int = combat.spawn_developer_unit(1, 1, target + Vector2i(1, 0))
	expect(combat.issue_artillery_strike(artillery, target), "Artillery valid range must be accepted")
	combat.tick(); expect(float(combat.get_unit(enemy)["health"]) < 32.0 and float(combat.get_unit(friend)["health"]) < 32.0, "Artillery splash must damage enemy and friendly units")
	expect(int(combat.get_unit(artillery)["weapon_cooldown"]) > 0, "Artillery cooldown must apply")
	combat.issue_defend(artillery); combat.tick(); expect(int(combat.get_unit(artillery)["weapon_cooldown"]) >= 0, "Artillery Defend must remain deterministic")
func missile_tests() -> void:
	var s := setup(); var map = s.map; var city = s.city; var combat = s.combat; var strategic = s.strategic; var silo: Vector2i = map.player_capital
	city.buildings[city.index(silo)] = CitySimulationScript.Building.MISSILE_SILO; city.industry_buildings.append(silo)
	city.resources[0] = 200.0; city.resources[2] = 10.0; city.resources[4] = 30.0; city.resources[6] = 30.0
	var money: float = city.resources[0]
	expect(strategic.queue_missile(silo), "Missile manufacture must start with resources")
	for tick in StrategicConfigScript.MISSILE_PRODUCTION_TICKS: strategic.tick()
	expect(int(strategic.ensure_silo(silo)["stored"]) == 1 and city.resources[0] < money, "Missile completes once and deducts resources")
	expect(not strategic.launch_missile(silo, Vector2i(-1, -1)), "Invalid missile target must reject")
	strategic.ensure_silo(silo)["stored"] = 2
	expect(strategic.launch_missile(silo, map.ai_capital), "Any distant valid in-bounds tile must be launchable without Recon Drone")
	expect(int(strategic.ensure_silo(silo)["stored"]) == 1 and strategic.missiles.size() == 1, "Launch must consume one missile once and create flight")
	expect(not strategic.launch_missile(silo, map.player_capital), "Silo cooldown must reject a second immediate launch")
	var duration: int = int(strategic.missiles[1]["duration"])
	expect(duration > StrategicConfigScript.MISSILE_MIN_FLIGHT_TICKS, "Cross-map missile duration should be distance-based")
	expect(map.scorch_count() == 0, "In-flight missile must not scorch tiles")
	for tick in duration: strategic.tick()
	expect(not bool(strategic.missiles[1]["alive"]), "Missile flight must deterministically complete")
	expect(map.has_scorch(map.ai_capital), "Impact center must be scorched")
	expect(map.scorch_count() == strategic.blast_tiles(map.ai_capital).size(), "Every authoritative blast tile must be scorched")
	var nearby_duration: int = strategic.missile_duration_ticks(silo, silo + Vector2i(1, 0))
	expect(nearby_duration < duration, "Nearby missile target must arrive faster than distant target")
	expect(nearby_duration == strategic.missile_duration_ticks(silo, silo + Vector2i(1, 0)), "Identical source and target must produce identical duration")
func sam_and_rubble_tests() -> void:
	var s := setup(); var map = s.map; var city = s.city; var combat = s.combat; var strategic = s.strategic; var sam: Vector2i = map.player_capital
	city.buildings[city.index(sam)] = CitySimulationScript.Building.SAM_SITE; city.industry_buildings.append(sam); city.power_coverage[city.index(sam)] = 1
	var road := sam + Vector2i(1, 0); city.roads[city.index(road)] = 1
	strategic.missiles[1] = {"id": 1, "owner": 2, "source": sam + Vector2i(2, 0), "target": sam, "progress": 0.0, "elapsed": 0, "duration": StrategicConfigScript.flight_duration_ticks(sam + Vector2i(2, 0), sam), "alive": true, "intercepted": false}
	strategic.tick(); expect(bool(strategic.missiles[1]["intercepted"]), "SAM must intercept deterministic hostile missile")
	expect(map.scorch_count() == 0, "Intercepted missile must not scorch or impact")
	var target: Vector2i = map.player_capital + Vector2i(3, 0); city.buildings[city.index(target)] = CitySimulationScript.Building.POWER_PLANT
	strategic.apply_blast(target); expect(city.has_rubble(target), "Destroyed structure must become rubble")
	expect(not city.place_road(target), "Rubble must block construction")
	expect(city.bulldoze(target) and not city.has_rubble(target), "Bulldoze must clear rubble")

func presentation_tests() -> void:
	var s := setup(); var map = s.map; var strategic = s.strategic
	var missile := {"source": map.player_capital, "target": map.ai_capital, "progress": 0}
	var source_position: Vector2 = strategic.missile_visual_position(missile)
	missile["progress"] = 1.0
	var target_position: Vector2 = strategic.missile_visual_position(missile)
	missile["progress"] = 0.5
	var peak_position: Vector2 = strategic.missile_visual_position(missile)
	expect(is_zero_approx(StrategicConfigScript.missile_arc_height(0.0)) and is_zero_approx(StrategicConfigScript.missile_arc_height(1.0)), "Missile arc must begin and end at zero height")
	expect(StrategicConfigScript.missile_arc_height(0.5) > 0.0 and StrategicConfigScript.missile_arc_height(0.5) >= StrategicConfigScript.missile_arc_height(0.25), "Missile arc must peak near midpoint")
	expect(source_position == IsoMathScript.tile_to_world(map.player_capital) and target_position == IsoMathScript.tile_to_world(map.ai_capital) and peak_position.y < (source_position.y + target_position.y) * 0.5, "Visual missile position must derive from authoritative progress")
	expect(strategic.blast_tiles(map.player_capital) == strategic.blast_tiles(map.player_capital), "Blast selection must remain deterministic")
	var renderer := CombatRendererScript.new(); renderer.configure(map, s.combat, strategic)
	renderer.set_missile_preview(true, map.ai_capital)
	expect(renderer.missile_preview_active and renderer.missile_preview_tile == map.ai_capital, "Target mode must enable configured blast preview state")
	renderer.set_missile_preview(false)
	expect(not renderer.missile_preview_active, "Leaving target mode must clear blast preview state")
	renderer.free()
