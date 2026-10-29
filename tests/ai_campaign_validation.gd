extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CombatConfigScript = preload("res://scripts/combat_config.gd")
const CampaignStateScript = preload("res://scripts/campaign_state.gd")
const PersistenceManagerScript = preload("res://scripts/persistence_manager.gd")

var failures: Array[String] = []
var temporary_path := "/tmp/city-game-ai-campaign-%d.json" % OS.get_process_id()

func _init() -> void:
	call_deferred("run_validation")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func run_validation() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	var ai = main.ai_campaign
	expect(ai != null and ai.economy != null and is_equal_approx(ai.economy.get_resource(CitySimulationScript.LedgerResource.MONEY), 500.0), "AI must begin with an independent normal starting ledger")
	expect(main.combat.ai_city_data == ai.economy and ai.economy.foreign_city_data == main.city, "AI and player city state must be linked only for occupancy and combat ownership")
	main.run_simulation_tick()
	main.run_simulation_tick()
	expect(ai.decision_count == 0, "AI planning must not run every fixed tick")
	main.run_simulation_tick()
	expect(ai.decision_count == 1 and ai.road_cursor == 1, "AI planning must use its deterministic three-tick cadence")

	# Normal startup must lay legal infrastructure and pay normal utility costs.
	for tick in 72:
		main.run_simulation_tick()
	expect(ai.has_building(CitySimulationScript.Building.POWER_PLANT) and ai.has_building(CitySimulationScript.Building.WATER_FACILITY), "AI must build legal power and water infrastructure")
	expect(ai.has_building(CitySimulationScript.Building.BARRACKS), "AI must build a normal military facility")
	expect(ai.economy.get_resource(CitySimulationScript.LedgerResource.MONEY) < 500.0 or ai.economy.occupied_households > 0, "AI construction must consume the normal ledger rather than create free infrastructure")
	expect(ai.economy.get_resource(CitySimulationScript.LedgerResource.MONEY) >= 0.0, "AI must not overspend into a negative money ledger")

	# Controlled test reserves accelerate normal queues; no AI-only production path is used.
	ai.economy.resources[CitySimulationScript.LedgerResource.MONEY] = 3000.0
	ai.economy.resources[CitySimulationScript.LedgerResource.MATERIALS] = 100.0
	ai.economy.resources[CitySimulationScript.LedgerResource.FUEL] = 100.0
	ai.economy.resources[CitySimulationScript.LedgerResource.MILITARY_SUPPLIES] = 100.0
	for tick in 120:
		main.run_simulation_tick()
	expect(ai.economy.is_technology_unlocked(CitySimulationScript.Technology.INDUSTRIAL_EXPANSION), "AI research must complete the normal first technology before advanced facilities")
	expect(ai.has_building(CitySimulationScript.Building.RESEARCH_LAB), "AI must use the legitimate Industrial Expansion unlock for its laboratory")
	var ai_units: Array[int] = ai.alive_ai_units()
	expect(ai_units.size() > 0, "AI must manufacture and deploy units through the normal inventory path")
	var has_defender := false
	for unit_id in ai_units:
		var unit: Dictionary = main.combat.get_unit(unit_id)
		if int(unit.get("command", -1)) == CombatConfigScript.COMMAND_DEFEND:
			has_defender = true
	expect(has_defender, "AI must retain a capital defense reserve using normal Defend orders")

	# A deterministic assembled force must receive ordinary movement orders and capture territory through CombatSimulation.
	while ai.alive_ai_units().size() < 5:
		var unit_id: int = main.combat.spawn_developer_unit(CombatConfigScript.OWNER_AI, CitySimulationScript.UnitType.INFANTRY, main.map_data.ai_capital)
		main.combat.units[unit_id]["strategic_managed"] = true
	ai.assign_force_orders()
	var attackers := 0
	for unit_id in ai.alive_ai_units():
		if int(main.combat.get_unit(unit_id).get("command", -1)) == CombatConfigScript.COMMAND_MOVE:
			attackers += 1
	expect(ai.phase == ai.Phase.ATTACK and attackers > 0, "AI must form a bounded offensive group with normal Move commands")
	var capture_tile: Vector2i = main.map_data.player_capital
	var capture_unit: int = main.combat.spawn_developer_unit(CombatConfigScript.OWNER_AI, CitySimulationScript.UnitType.INFANTRY, capture_tile)
	main.combat.units[capture_unit]["strategic_managed"] = true
	main.run_simulation_tick()
	main.run_simulation_tick()
	expect(main.combat.player_capital_owner == CombatConfigScript.OWNER_AI and main.campaign.phase == CampaignStateScript.Phase.PLAYER_DEFEAT, "AI ground capture must use the authoritative capital rule and enter one-shot defeat")
	expect(main.hud.victory_panel.visible and main.hud.victory_title_label.text.contains("DEFEAT"), "Defeat must present a clear paused recovery state")
	expect(not main.run_simulation_tick() and main.campaign.defeat_event_count == 1, "Defeat must pause and never repeat")

	# Persist an ACTIVE AI controller independently from the defeat check.
	main.regenerate_world(main.map_data.seed)
	ai = main.ai_campaign
	ai.simulation_ticks = 27
	ai.decision_count = 9
	ai.phase = ai.Phase.PREPARE
	ai.economy.resources[CitySimulationScript.LedgerResource.MONEY] = 777.0
	var manager = PersistenceManagerScript.new()
	expect(manager.save_game(temporary_path, main.map_data, main.city, main.combat, main.strategic, main.campaign, "manual", -1, ai), "AI campaign state must save in schema v1")
	var loaded := manager.load_game(temporary_path)
	expect(not loaded.is_empty() and loaded["ai_campaign"].decision_count == 9 and is_equal_approx(loaded["ai_campaign"].economy.get_resource(CitySimulationScript.LedgerResource.MONEY), 777.0), "AI economy and decision state must round-trip without reset")
	expect(loaded["ai_campaign"].economy.foreign_city_data == loaded["city"] and loaded["combat"].ai_city_data == loaded["ai_campaign"].economy, "Loaded AI references must reconnect to the reconstructed authoritative state")

	if failures.is_empty():
		print("AI Campaign validation passed: deterministic economy, research, normal production, defense, offense, defeat, and persistence.")
	else:
		for failure in failures:
			push_error(failure)
	var result := 0 if failures.is_empty() else 1
	main.queue_free()
	await process_frame
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	quit(result)
