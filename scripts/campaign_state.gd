class_name CampaignState
extends RefCounted

const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CityConfigScript = preload("res://scripts/city_config.gd")
const CombatConfigScript = preload("res://scripts/combat_config.gd")

enum Phase { ACTIVE, PLAYER_VICTORY, SANDBOX, PLAYER_DEFEAT }

const DEFEATED_NATION_NAME := "Prototype AI Nation"

var phase := Phase.ACTIVE
var elapsed_ticks := 0
var victory_event_count := 0
var defeat_event_count := 0
var defeated_nation := ""
var defeated_capital := Vector2i(-1, -1)
var victory_stats: Dictionary = {}

func simulation_enabled() -> bool:
	return phase == Phase.ACTIVE or phase == Phase.SANDBOX

func is_victory_pending() -> bool:
	return phase == Phase.PLAYER_VICTORY

func is_defeat_pending() -> bool:
	return phase == Phase.PLAYER_DEFEAT

func is_outcome_pending() -> bool:
	return is_victory_pending() or is_defeat_pending()

func record_simulation_tick() -> void:
	if simulation_enabled():
		elapsed_ticks += 1

func observe_capital_ownership(combat, city, map_data) -> bool:
	if phase != Phase.ACTIVE:
		return false
	if combat.ai_capital_owner == CombatConfigScript.OWNER_PLAYER:
		phase = Phase.PLAYER_VICTORY
		victory_event_count += 1
		defeated_nation = DEFEATED_NATION_NAME
		defeated_capital = map_data.ai_capital
		victory_stats = build_victory_stats(city, combat)
		return true
	if combat.player_capital_owner == CombatConfigScript.OWNER_AI:
		phase = Phase.PLAYER_DEFEAT
		defeat_event_count += 1
		defeated_nation = "Player"
		defeated_capital = map_data.player_capital
		victory_stats = build_victory_stats(city, combat)
		return true
	return false

func continue_in_sandbox() -> bool:
	if phase != Phase.PLAYER_VICTORY:
		return false
	phase = Phase.SANDBOX
	return true

func build_victory_stats(city, combat) -> Dictionary:
	var player_forces := 0
	var enemy_forces := 0
	for unit_id in combat.sorted_unit_ids():
		var unit: Dictionary = combat.get_unit(unit_id)
		if not bool(unit.get("alive", false)):
			continue
		if int(unit.get("owner", CombatConfigScript.OWNER_NEUTRAL)) == CombatConfigScript.OWNER_PLAYER:
			player_forces += 1
		elif int(unit.get("owner", CombatConfigScript.OWNER_NEUTRAL)) == CombatConfigScript.OWNER_AI:
			enemy_forces += 1
	return {
		"elapsed_ticks": elapsed_ticks,
		"elapsed_seconds": float(elapsed_ticks) * CityConfigScript.TICK_SECONDS,
		"population": city.occupied_households,
		"money": city.get_resource(CitySimulationScript.LedgerResource.MONEY),
		"food": city.get_resource(CitySimulationScript.LedgerResource.FOOD),
		"materials": city.get_resource(CitySimulationScript.LedgerResource.MATERIALS),
		"fuel": city.get_resource(CitySimulationScript.LedgerResource.FUEL),
		"military_supplies": city.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES),
		"player_forces": player_forces,
		"enemy_forces": enemy_forces,
	}
