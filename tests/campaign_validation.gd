extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const CampaignStateScript = preload("res://scripts/campaign_state.gd")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CombatConfigScript = preload("res://scripts/combat_config.gd")

var failures: Array[String] = []
var autosave_directory := "/tmp/city-game-campaign-autosave-%d" % OS.get_process_id()

func _init() -> void:
	call_deferred("run_validation")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run_validation() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	main.persistence.autosave_directory = autosave_directory

	expect(main.campaign.phase == CampaignStateScript.Phase.ACTIVE, "Campaign must begin active")
	expect(main.combat.ai_capital_owner == CombatConfigScript.OWNER_AI, "Enemy capital must begin under AI ownership")
	expect(not main.campaign.observe_capital_ownership(main.combat, main.city, main.map_data), "Uncaptured capital must not trigger victory")

	var preserved_tile := find_ground(main)
	var damage_tile := find_ground(main, [preserved_tile])
	var ai_unit_tile := find_ground(main, [preserved_tile, damage_tile])
	main.map_data.mark_scorched(damage_tile)
	main.city.rubble[main.city.index(damage_tile)] = 1
	main.city.buildings[main.city.index(preserved_tile)] = CitySimulationScript.Building.POWER_PLANT
	main.city.resources[CitySimulationScript.LedgerResource.MONEY] = 4321.0
	main.city.resources[CitySimulationScript.LedgerResource.MATERIALS] = 87.0
	main.city.completed_technologies[CitySimulationScript.Technology.INDUSTRIAL_EXPANSION] = 1
	main.strategic.silos[preserved_tile] = {"stored": 1, "cooldown": 2, "production": 0}
	var ai_unit: int = main.combat.spawn_developer_unit(CombatConfigScript.OWNER_AI, CitySimulationScript.UnitType.TANK, ai_unit_tile)
	var capturing_unit: int = main.combat.spawn_developer_unit(CombatConfigScript.OWNER_PLAYER, CitySimulationScript.UnitType.INFANTRY, main.map_data.ai_capital)
	expect(ai_unit >= 0 and capturing_unit >= 0, "Player and AI preservation test forces must deploy on valid ground")

	main.run_simulation_tick()
	expect(main.campaign.phase == CampaignStateScript.Phase.ACTIVE, "Capital must not trigger victory before the existing capture duration")
	main.run_simulation_tick()
	expect(main.combat.ai_capital_owner == CombatConfigScript.OWNER_PLAYER, "Existing combat capture must transfer enemy capital ownership")
	expect(main.campaign.phase == CampaignStateScript.Phase.PLAYER_VICTORY, "Valid capital capture must enter player-victory state")
	expect(main.campaign.victory_event_count == 1, "Victory must emit exactly once")
	expect(main.campaign.defeated_nation == CampaignStateScript.DEFEATED_NATION_NAME and main.campaign.defeated_capital == main.map_data.ai_capital, "Victory state must identify the defeated nation and capital")
	expect(main.hud.victory_panel.visible and not main.hud.root_panel.visible, "Victory modal must replace normal contextual controls")
	expect(main.hud.victory_summary_label.text.contains("Population:") and main.hud.victory_summary_label.text.contains("Surviving forces:"), "Victory summary must expose available campaign statistics")
	expect(main.hud.continue_sandbox_button.text == "Continue in Sandbox", "Victory modal must expose the required continuation action")

	var map_ref = main.map_data
	var city_ref = main.city
	var combat_ref = main.combat
	var strategic_ref = main.strategic
	var checksum_before: int = main.map_data.world_checksum()
	var buildings_before: PackedByteArray = main.city.buildings.duplicate()
	var resources_before: PackedFloat64Array = main.city.resources.duplicate()
	var research_before: PackedByteArray = main.city.completed_technologies.duplicate()
	var territory_before: PackedByteArray = main.combat.territory.duplicate()
	var units_before: Dictionary = main.combat.units.duplicate(true)
	var silos_before: Dictionary = main.strategic.silos.duplicate(true)
	var city_ticks_at_victory: int = main.city.tick_count

	expect(not main.run_simulation_tick() and main.city.tick_count == city_ticks_at_victory, "Simulation must pause while the victory summary is open")
	expect(not main.campaign.observe_capital_ownership(main.combat, main.city, main.map_data) and main.campaign.victory_event_count == 1, "Repeated ownership checks must not repeat victory")

	main.hud.continue_sandbox_button.pressed.emit()
	expect(main.campaign.phase == CampaignStateScript.Phase.SANDBOX, "Continue must enter post-victory sandbox")
	expect(not main.hud.victory_panel.visible and main.hud.root_panel.visible, "Continue must close the summary and restore normal controls")
	expect(is_same(main.map_data, map_ref) and is_same(main.city, city_ref) and is_same(main.combat, combat_ref) and is_same(main.strategic, strategic_ref), "Continue must retain all simulation object identities")
	expect(main.map_data.world_checksum() == checksum_before and main.map_data.has_scorch(damage_tile) and main.city.has_rubble(damage_tile), "Terrain changes and damage must survive sandbox continuation")
	expect(main.city.buildings == buildings_before and main.city.resources == resources_before and main.city.completed_technologies == research_before, "Buildings, resources, and research must survive sandbox continuation")
	expect(main.combat.territory == territory_before and main.combat.units == units_before, "Territory, units, orders, and health must survive sandbox continuation")
	expect(main.strategic.silos == silos_before, "Strategic weapon state must survive sandbox continuation")
	expect(main.map_data.ai_capital == main.campaign.defeated_capital, "Captured capital must remain physically present")

	expect(main.run_simulation_tick() and main.city.tick_count == city_ticks_at_victory + 1, "Simulation must resume normally in sandbox")
	expect(main.campaign.phase == CampaignStateScript.Phase.SANDBOX and main.campaign.victory_event_count == 1 and not main.hud.victory_panel.visible, "Victory must never reopen automatically in sandbox")

	if failures.is_empty():
		print("Campaign Part 1 validation passed: one-shot capital victory, summary, preservation, and sandbox resume.")
	else:
		for failure in failures:
			push_error(failure)
	var result := 0 if failures.is_empty() else 1
	main.queue_free()
	main = null
	await process_frame
	await process_frame
	for slot in 3:
		var autosave_path := "%s/autosave_%d.json" % [autosave_directory, slot]
		if FileAccess.file_exists(autosave_path):
			DirAccess.remove_absolute(autosave_path)
	DirAccess.remove_absolute(autosave_directory)
	quit(result)

func find_ground(main, excluded: Array[Vector2i] = []) -> Vector2i:
	for y in main.map_data.size.y:
		for x in main.map_data.size.x:
			var tile := Vector2i(x, y)
			if main.map_data.is_traversable_ground(tile) and not main.map_data.is_capital_marker(tile) and not excluded.has(tile):
				return tile
	return Vector2i(-1, -1)
