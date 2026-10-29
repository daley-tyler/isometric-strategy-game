extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const PersistenceManagerScript = preload("res://scripts/persistence_manager.gd")
const CampaignStateScript = preload("res://scripts/campaign_state.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CombatConfigScript = preload("res://scripts/combat_config.gd")

var failures: Array[String] = []
var temporary_directory := "/tmp/city-game-persistence-validation-%d" % OS.get_process_id()

func _init() -> void:
	call_deferred("run_validation")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run_validation() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.persistence.manual_save_path = temporary_directory + "/manual_save.json"
	main.persistence.autosave_directory = temporary_directory + "/autosaves"
	main.persistence.configure_autosave_rotation()

	var terrain_tile := find_ground(main)
	var marker_tile := find_ground(main, [terrain_tile])
	var damage_tile := find_ground(main, [terrain_tile, marker_tile])
	var road_tile := find_ground(main, [terrain_tile, marker_tile, damage_tile])
	var zone_tile := find_ground(main, [terrain_tile, marker_tile, damage_tile, road_tile])
	var building_tile := find_ground(main, [terrain_tile, marker_tile, damage_tile, road_tile, zone_tile])
	var sam_tile := find_ground(main, [terrain_tile, marker_tile, damage_tile, road_tile, zone_tile, building_tile])
	var player_tile := find_ground(main, [terrain_tile, marker_tile, damage_tile, road_tile, zone_tile, building_tile, sam_tile])
	var enemy_tile := find_ground(main, [terrain_tile, marker_tile, damage_tile, road_tile, zone_tile, building_tile, sam_tile, player_tile])
	var mover_tile := find_ground(main, [terrain_tile, marker_tile, damage_tile, road_tile, zone_tile, building_tile, sam_tile, player_tile, enemy_tile])
	var destination := find_ground(main, [terrain_tile, marker_tile, damage_tile, road_tile, zone_tile, building_tile, sam_tile, player_tile, enemy_tile, mover_tile])

	main.map_data.seed = 987654
	main.map_data.terrain[main.map_data.index(terrain_tile)] = MapDataScript.Terrain.HILL
	main.map_data.place_marker(marker_tile)
	main.map_data.mark_scorched(damage_tile)
	main.city.roads[main.city.index(road_tile)] = 1
	main.city.zones[main.city.index(zone_tile)] = CitySimulationScript.Zone.RESIDENTIAL
	main.city.buildings[main.city.index(building_tile)] = CitySimulationScript.Building.MISSILE_SILO
	main.city.rubble[main.city.index(damage_tile)] = 1
	var industry_tiles: Array[Vector2i] = [building_tile]
	main.city.industry_buildings = industry_tiles
	main.city.resources = PackedFloat64Array([4321.5, 19.0, 88.0, 77.0, 66.0, 55.0, 44.0])
	main.city.household_capacity = 24
	main.city.occupied_households = 19
	main.city.job_capacity = 12
	main.city.employed_workforce = 9
	main.city.operation_workforce_remaining = 10
	main.city.operation_power_remaining = 73.0
	main.city.tick_count = 42
	main.city.completed_technologies[CitySimulationScript.Technology.INDUSTRIAL_EXPANSION] = 1
	main.city.active_technology = CitySimulationScript.Technology.REFINING
	main.city.research_progress = 7.5
	main.city.research_status = "Researching Refining: 7.5/12.0"
	main.city.produced_units[CitySimulationScript.UnitType.INFANTRY] = 2
	main.city.selected_import_resource = CitySimulationScript.LedgerResource.FUEL
	var import_orders: Array[Dictionary] = [{"resource": CitySimulationScript.LedgerResource.FOOD, "quantity": 20.0, "cost": 40.0, "remaining": 2}]
	var manufacturing_tile := find_ground(main, [terrain_tile, marker_tile, damage_tile, road_tile, zone_tile, building_tile, sam_tile, player_tile, enemy_tile, mover_tile, destination])
	main.city.buildings[main.city.index(manufacturing_tile)] = CitySimulationScript.Building.BARRACKS
	main.city.industry_buildings.append(manufacturing_tile)
	var manufacturing_orders: Array[Dictionary] = [{"tile": manufacturing_tile, "unit": CitySimulationScript.UnitType.INFANTRY, "remaining": 3}]
	main.city.import_orders = import_orders
	main.city.manufacturing_orders = manufacturing_orders
	main.city.rebuild_coverage()

	var player_id: int = main.combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.TANK, player_tile)
	var enemy_id: int = main.combat.spawn_developer_unit(CombatConfigScript.OWNER_AI, CitySimulationScript.UnitType.INFANTRY, enemy_tile)
	var mover_id: int = main.combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.INFANTRY, mover_tile)
	expect(player_id > 0 and enemy_id > 0 and mover_id > 0, "Persistence test units must spawn")
	main.combat.issue_attack(player_id, enemy_id)
	main.combat.issue_move(mover_id, destination)
	main.combat.units[player_id]["health"] = 53.5
	main.combat.units[player_id]["weapon_cooldown"] = 4
	main.combat.units[enemy_id]["health"] = 17.0
	main.combat.territory[main.map_data.index(zone_tile)] = CombatConfigScript.OWNER_PLAYER
	main.combat.territory[main.map_data.index(building_tile)] = CombatConfigScript.OWNER_AI
	main.combat.capital_progress["ai:%d" % player_id] = 1
	main.combat.terrain_capture_progress[mover_id] = 1

	main.strategic.tick_count = 31
	main.strategic.silos[building_tile] = {"stored": 2, "cooldown": 3, "production": 1}
	main.strategic.sam_cooldowns[sam_tile] = 4
	main.strategic.missiles[7] = {"id": 7, "owner": CombatConfigScript.OWNER_PLAYER, "source": building_tile, "target": main.map_data.ai_capital, "progress": 0.375, "elapsed": 3, "duration": 8, "alive": true, "intercepted": false}
	main.strategic.next_missile_id = 8
	main.campaign.elapsed_ticks = 42

	var expected_checksum: int = main.map_data.world_checksum()
	var expected_resources: PackedFloat64Array = main.city.resources.duplicate()
	var expected_buildings: PackedByteArray = main.city.buildings.duplicate()
	var expected_units: Dictionary = main.combat.units.duplicate(true)
	var expected_territory: PackedByteArray = main.combat.territory.duplicate()
	var expected_silos: Dictionary = main.strategic.silos.duplicate(true)
	var expected_missiles: Dictionary = main.strategic.missiles.duplicate(true)
	var old_map = main.map_data
	var old_city = main.city
	var old_combat = main.combat
	var old_strategic = main.strategic
	var hud_ref = main.hud
	var world_renderer_ref = main.world_renderer
	var combat_renderer_ref = main.combat_renderer

	main.hud.save_button.pressed.emit()
	var measured_save_msec: float = main.persistence.last_save_duration_msec
	var measured_size: int = main.persistence.last_save_size_bytes
	expect(main.action_feedback == "Game saved" and FileAccess.file_exists(main.persistence.manual_save_path), "Manual Save control must write the configured save")
	var document: Dictionary = main.persistence.parse_document(main.persistence.manual_save_path)
	expect(int(document.get("version", -1)) == PersistenceManagerScript.SAVE_VERSION, "Save format version 1 must be written and recognized")

	main.map_data.seed = 1
	main.map_data.terrain[main.map_data.index(terrain_tile)] = MapDataScript.Terrain.COAST
	main.city.resources.fill(0.0)
	main.city.buildings.fill(CitySimulationScript.Building.NONE)
	main.combat.units.clear()
	main.combat.territory.fill(CombatConfigScript.OWNER_NEUTRAL)
	main.strategic.silos.clear()
	main.strategic.missiles.clear()
	main.campaign.elapsed_ticks = 0
	main.selected_tile = zone_tile
	main.hud.load_button.pressed.emit()
	var measured_load_msec: float = main.persistence.last_load_duration_msec

	expect(main.action_feedback == "Game loaded", "Manual Load control must report success")
	expect(main.map_data.seed == 987654 and main.map_data.world_checksum() == expected_checksum, "Map seed and exact terrain modifications must survive round-trip")
	expect(main.map_data.has_marker(marker_tile) and main.map_data.has_scorch(damage_tile), "Marker and scorch layers must survive")
	expect(main.city.buildings == expected_buildings and main.city.resources == expected_resources and main.city.has_rubble(damage_tile), "Buildings, resources, and rubble must restore saved values")
	expect(main.city.occupied_households == 19 and main.city.employed_workforce == 9 and main.city.household_capacity == 24 and main.city.job_capacity == 12, "Population and workforce state must survive")
	expect(main.city.active_technology == CitySimulationScript.Technology.REFINING and is_equal_approx(main.city.research_progress, 7.5) and main.city.is_technology_unlocked(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION), "Research and progression state must survive")
	expect(main.city.import_orders.size() == 1 and main.city.manufacturing_orders.size() == 1 and main.city.get_produced_unit_count(CitySimulationScript.UnitType.INFANTRY) == 2, "Orders and produced inventory must survive without duplication")
	expect(main.combat.units == expected_units and main.combat.territory == expected_territory and main.combat.units.size() == 3, "Units and territory must restore exactly without duplication")
	expect(int(main.combat.units[player_id]["target_id"]) == enemy_id and int(main.combat.units[player_id]["command"]) == CombatConfigScript.COMMAND_ATTACK, "Stable unit IDs must reconnect active attack targets")
	expect(not Array(main.combat.units[mover_id]["path"]).is_empty() and Array(main.combat.units[mover_id]["path"])[-1] == destination, "Active movement destination and path must survive")
	expect(is_equal_approx(float(main.combat.units[player_id]["health"]), 53.5) and int(main.combat.units[player_id]["weapon_cooldown"]) == 4, "Unit health and gameplay cooldown must survive")
	expect(main.strategic.silos == expected_silos and main.strategic.missiles == expected_missiles and int(main.strategic.sam_cooldowns[sam_tile]) == 4, "Missile, silo, and SAM gameplay state must survive")
	expect(main.campaign.phase == CampaignStateScript.Phase.ACTIVE and main.campaign.elapsed_ticks == 42, "ACTIVE campaign phase and deterministic time must survive")
	expect(not is_same(main.map_data, old_map) and not is_same(main.city, old_city) and not is_same(main.combat, old_combat) and not is_same(main.strategic, old_strategic), "Load must reconstruct authoritative simulation objects")
	expect(is_same(main.city.map_data, main.map_data) and is_same(main.combat.map_data, main.map_data) and is_same(main.combat.city_data, main.city) and is_same(main.strategic.combat_data, main.combat), "Reconstructed systems must reference the newly loaded authoritative state")
	expect(is_same(main.hud, hud_ref) and is_same(main.world_renderer, world_renderer_ref) and is_same(main.combat_renderer, combat_renderer_ref), "Load must reuse HUD and renderer nodes rather than duplicate them")
	expect(main.selected_tile == Vector2i(-1, -1) and main.combat.selected_unit_id == -1 and main.interaction_mode.is_empty(), "Load must clear stale selection and interaction state")

	var capturing_id: int = main.combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.INFANTRY, main.map_data.ai_capital)
	expect(capturing_id > 0, "Loaded ACTIVE campaign must allow a valid capture force")
	main.run_simulation_tick()
	main.run_simulation_tick()
	expect(main.campaign.phase == CampaignStateScript.Phase.PLAYER_VICTORY and main.hud.victory_panel.visible, "Loaded ACTIVE campaign must continue normal victory detection")
	main.hud_save_game()
	expect(main.action_feedback == "Cannot save while victory summary is open", "Manual saving must be explicitly disabled while the victory summary is open")
	var victory_path := temporary_directory + "/victory_save.json"
	expect(main.persistence.save_game(victory_path, main.map_data, main.city, main.combat, main.strategic, main.campaign), "Data layer must support a logically consistent PLAYER_VICTORY save")
	var loaded_victory: Dictionary = main.persistence.load_game(victory_path)
	main.apply_loaded_state(loaded_victory)
	var victory_events: int = main.campaign.victory_event_count
	expect(main.campaign.phase == CampaignStateScript.Phase.PLAYER_VICTORY and main.hud.victory_panel.visible, "PLAYER_VICTORY load must restore its summary without replaying capture")
	expect(not main.campaign.observe_capital_ownership(main.combat, main.city, main.map_data) and main.campaign.victory_event_count == victory_events, "PLAYER_VICTORY load must not duplicate the victory event")
	main.hud.continue_sandbox_button.pressed.emit()
	expect(main.campaign.phase == CampaignStateScript.Phase.SANDBOX, "Continue must still enter SANDBOX after a victory-state load")
	expect(not main.persistence.latest_autosave_path().is_empty(), "Entering sandbox must create a recoverable autosave")
	var sandbox_money: float = main.city.get_resource(CitySimulationScript.LedgerResource.MONEY)
	main.city.resources[CitySimulationScript.LedgerResource.MONEY] = 0.0
	main.hud.load_autosave_button.pressed.emit()
	expect(main.campaign.phase == CampaignStateScript.Phase.SANDBOX and is_equal_approx(main.city.get_resource(CitySimulationScript.LedgerResource.MONEY), sandbox_money), "Load Latest Autosave control must restore the newest rotating slot")
	main.hud.save_button.pressed.emit()
	main.campaign.phase = CampaignStateScript.Phase.ACTIVE
	main.combat.ai_capital_owner = CombatConfigScript.OWNER_AI
	main.hud.load_button.pressed.emit()
	expect(main.campaign.phase == CampaignStateScript.Phase.SANDBOX and main.combat.ai_capital_owner == CombatConfigScript.OWNER_PLAYER, "SANDBOX save must preserve the captured capital")
	expect(not main.hud.victory_panel.visible and main.run_simulation_tick(), "SANDBOX load must not reopen victory and must resume simulation")
	expect(main.campaign.phase == CampaignStateScript.Phase.SANDBOX and main.campaign.victory_event_count == victory_events, "SANDBOX simulation must never retrigger campaign victory")

	var auto_manager = PersistenceManagerScript.new()
	auto_manager.autosave_directory = temporary_directory + "/rotation"
	auto_manager.configure_autosave_rotation()
	for index in 4:
		expect(auto_manager.save_autosave(main.map_data, main.city, main.combat, main.strategic, main.campaign), "Autosave %d must succeed" % index)
	var sequences: Array[int] = []
	for slot in PersistenceManagerScript.AUTOSAVE_SLOTS:
		var autosave_path: String = auto_manager.autosave_path(slot)
		expect(FileAccess.file_exists(autosave_path), "Autosave rotation must populate slot %d" % slot)
		var autosave_document: Dictionary = auto_manager.parse_document(autosave_path)
		sequences.append(int(Dictionary(autosave_document.get("metadata", {})).get("autosave_sequence", -1)))
	sequences.sort()
	expect(sequences == [1, 2, 3], "Three autosave slots must rotate instead of overwriting one target")
	var latest_autosave: String = auto_manager.latest_autosave_path()
	expect(not latest_autosave.is_empty() and int(Dictionary(auto_manager.parse_document(latest_autosave).get("metadata", {})).get("autosave_sequence", -1)) == 3, "Latest-autosave lookup must select the highest sequence")
	var resumed_auto_manager = PersistenceManagerScript.new()
	resumed_auto_manager.autosave_directory = temporary_directory + "/rotation"
	resumed_auto_manager.configure_autosave_rotation()
	expect(resumed_auto_manager.autosave_sequence == 4 and resumed_auto_manager.autosave_slot == 1, "Autosave rotation must resume from the highest saved sequence after restart")

	var unsupported: Dictionary = auto_manager.create_save_data(main.map_data, main.city, main.combat, main.strategic, main.campaign)
	unsupported["version"] = PersistenceManagerScript.SAVE_VERSION + 1
	var unsupported_path := temporary_directory + "/unsupported.json"
	write_text(unsupported_path, JSON.stringify(unsupported))
	var checksum_before_rejection: int = main.map_data.world_checksum()
	expect(auto_manager.load_game(unsupported_path).is_empty() and auto_manager.last_error.contains("Unsupported save version") and main.map_data.world_checksum() == checksum_before_rejection, "Unsupported future save versions must fail clearly without changing live state")

	print("Persistence metrics: %d bytes, save %.2f ms, load %.2f ms" % [measured_size, measured_save_msec, measured_load_msec])
	if failures.is_empty():
		print("Persistence validation passed: schema v1, exact reconstruction, stable IDs, campaign resume, and rotating autosaves.")
	else:
		for failure in failures:
			push_error(failure)
	var result := 0 if failures.is_empty() else 1
	main.queue_free()
	main = null
	await process_frame
	await process_frame
	cleanup_files()
	quit(result)

func find_ground(main, excluded: Array[Vector2i] = []) -> Vector2i:
	for y in main.map_data.size.y:
		for x in main.map_data.size.x:
			var tile := Vector2i(x, y)
			if main.map_data.is_traversable_ground(tile) and not main.map_data.is_capital_marker(tile) and not excluded.has(tile):
				return tile
	return Vector2i(-1, -1)

func write_text(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()

func cleanup_files() -> void:
	for path in [temporary_directory + "/manual_save.json", temporary_directory + "/victory_save.json", temporary_directory + "/unsupported.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	for directory in [temporary_directory + "/autosaves", temporary_directory + "/rotation"]:
		for slot in PersistenceManagerScript.AUTOSAVE_SLOTS:
			var path := "%s/autosave_%d.json" % [directory, slot]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(temporary_directory)
