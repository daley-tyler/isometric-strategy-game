class_name CombatSimulation
extends RefCounted

const CombatConfigScript = preload("res://scripts/combat_config.gd")
const MapDataScript = preload("res://scripts/map_data.gd")

var map_data
var city_data
var ai_city_data
var units: Dictionary = {}
var territory := PackedByteArray()
var next_unit_id := 1
var selected_unit_id := -1
var last_action_reason := ""
var status_message := ""
var ai_capital_owner := CombatConfigScript.OWNER_AI
var player_capital_owner := CombatConfigScript.OWNER_PLAYER
var capital_progress: Dictionary = {}
var terrain_capture_progress: Dictionary = {}
var path_rebuild_count := 0
var terrain_visual_changes := 0
var damaged_structure_tiles: Array[Vector2i] = []

func _init(data, city = null) -> void:
	map_data = data
	city_data = city
	territory.resize(data.size.x * data.size.y)

func get_unit(unit_id: int) -> Dictionary:
	return units.get(unit_id, {})

func unit_at(tile: Vector2i, owner: int = CombatConfigScript.OWNER_NEUTRAL) -> int:
	for unit_id in sorted_unit_ids():
		var unit: Dictionary = units[unit_id]
		if bool(unit["alive"]) and unit["tile"] == tile and (owner == CombatConfigScript.OWNER_NEUTRAL or int(unit["owner"]) == owner):
			return unit_id
	return -1

func select_unit_at(tile: Vector2i, owner: int = CombatConfigScript.OWNER_PLAYER) -> bool:
	var found := unit_at(tile, owner)
	selected_unit_id = found
	return found >= 0

func clear_selection() -> void:
	selected_unit_id = -1

func spawn_developer_unit(owner: int, unit_type: int, tile: Vector2i) -> int:
	if not valid_deployment_tile(unit_type, tile):
		return -1
	return create_unit(owner, unit_type, tile)

func deploy_produced_unit(unit_type: int, facility_tile: Vector2i) -> bool:
	return deploy_produced_unit_for_owner(city_data, CombatConfigScript.OWNER_PLAYER, unit_type, facility_tile)

func deploy_produced_unit_for_owner(source_city, owner: int, unit_type: int, facility_tile: Vector2i) -> bool:
	if source_city == null or not CombatConfigScript.UNIT_DATA.has(unit_type):
		return reject("Cannot deploy: Invalid unit")
	if source_city.get_produced_unit_count(unit_type) <= 0:
		return reject("Cannot deploy: No produced unit available")
	if not map_data.is_valid(facility_tile):
		return reject("Cannot deploy: Invalid destination")
	var required_facility: int = int(source_city.unit_definition(unit_type).get("facility", -1))
	var capital: Vector2i = map_data.ai_capital if owner == CombatConfigScript.OWNER_AI else map_data.player_capital
	var at_capital: bool = facility_tile == capital
	if not at_capital and source_city.get_building(facility_tile) != required_facility:
		return reject("Cannot deploy: Select the required facility or capital")
	if not valid_deployment_tile(unit_type, facility_tile):
		return reject("Cannot deploy: Invalid terrain")
	source_city.produced_units[unit_type] -= 1
	create_unit(owner, unit_type, facility_tile)
	return accept("Deployed %s" % String(CombatConfigScript.UNIT_DATA[unit_type]["name"]))

func create_unit(owner: int, unit_type: int, tile: Vector2i) -> int:
	var data: Dictionary = CombatConfigScript.UNIT_DATA[unit_type]
	var unit_id := next_unit_id
	next_unit_id += 1
	units[unit_id] = {
		"id": unit_id, "owner": owner, "type": unit_type, "tile": tile, "world_position": tile,
		"health": float(data["health"]), "max_health": float(data["health"]), "armor": float(data["armor"]),
		"damage": float(data["damage"]), "range": int(data["range"]), "movement_speed": float(data["speed"]),
		"air": bool(data["air"]), "command": CombatConfigScript.COMMAND_IDLE, "target_id": -1,
		"path": [], "path_index": 0, "move_wait": 0, "alive": true, "defend_tile": tile,
		"weapon_cooldown": 0,
		"strategic_managed": false,
	}
	return unit_id

func valid_deployment_tile(unit_type: int, tile: Vector2i) -> bool:
	return map_data.is_valid(tile) and (bool(CombatConfigScript.UNIT_DATA[unit_type]["air"]) or map_data.is_traversable_ground(tile))

func issue_move(unit_id: int, destination: Vector2i) -> bool:
	var unit := get_unit(unit_id)
	if unit.is_empty() or not bool(unit["alive"]): return reject("No unit selected")
	var path := find_path(unit["tile"], destination, bool(unit["air"]))
	if path.is_empty() and unit["tile"] != destination: return reject("Cannot move: No path")
	unit["command"] = CombatConfigScript.COMMAND_MOVE
	unit["target_id"] = -1
	unit["path"] = path
	unit["path_index"] = 1
	unit["move_wait"] = 0
	path_rebuild_count += 1
	return accept("Move ordered")

func issue_attack(unit_id: int, target_id: int) -> bool:
	var unit := get_unit(unit_id)
	var target := get_unit(target_id)
	if unit.is_empty() or not bool(unit["alive"]): return reject("No unit selected")
	if target.is_empty() or not bool(target["alive"]): return reject("Cannot attack: Invalid target")
	if int(unit["owner"]) == int(target["owner"]): return reject("Cannot attack: Friendly target")
	if int(unit["type"]) == 3:
		return issue_artillery_strike(unit_id, target["tile"])
	unit["command"] = CombatConfigScript.COMMAND_ATTACK
	unit["target_id"] = target_id
	unit["path"] = []
	unit["path_index"] = 0
	return accept("Attack ordered")

func issue_artillery_strike(unit_id: int, target_tile: Vector2i) -> bool:
	var unit := get_unit(unit_id)
	if unit.is_empty() or not bool(unit["alive"]) or int(unit["type"]) != 3: return reject("Invalid artillery")
	if not map_data.is_valid(target_tile): return reject("Invalid target")
	if not Array(unit["path"]).is_empty() or int(unit["command"]) == CombatConfigScript.COMMAND_MOVE: return reject("Artillery must stop before firing")
	var distance := Vector2i(unit["tile"]).distance_to(target_tile)
	if distance < CombatConfigScript.ARTILLERY_MIN_RANGE: return reject("Target inside minimum range")
	if distance > CombatConfigScript.ARTILLERY_MAX_RANGE: return reject("Target outside maximum range")
	if int(unit["weapon_cooldown"]) > 0: return reject("Artillery cooling down")
	unit["command"] = CombatConfigScript.COMMAND_ATTACK
	unit["target_tile"] = target_tile
	unit["target_id"] = -1
	return accept("Artillery strike ordered")

func issue_defend(unit_id: int) -> bool:
	var unit := get_unit(unit_id)
	if unit.is_empty() or not bool(unit["alive"]): return reject("No unit selected")
	unit["command"] = CombatConfigScript.COMMAND_DEFEND
	unit["defend_tile"] = unit["tile"]
	unit["target_id"] = -1
	unit["path"] = []
	return accept("Defend ordered")

func issue_stop(unit_id: int) -> bool:
	var unit := get_unit(unit_id)
	if unit.is_empty() or not bool(unit["alive"]): return reject("No unit selected")
	unit["command"] = CombatConfigScript.COMMAND_STOP
	unit["target_id"] = -1
	unit["path"] = []
	unit["path_index"] = 0
	return accept("Stop ordered")

func find_path(start: Vector2i, destination: Vector2i, air: bool) -> Array[Vector2i]:
	if not map_data.is_valid(start) or not map_data.is_valid(destination) or (not air and not map_data.is_traversable_ground(destination)):
		return []
	if start == destination: return [start]
	var visited := PackedByteArray(); visited.resize(map_data.size.x * map_data.size.y)
	var previous: Dictionary = {}; var queue: Array[Vector2i] = [start]; visited[map_data.index(start)] = 1
	var cursor := 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]; cursor += 1
		for direction in MapDataScript.CARDINAL_DIRECTIONS:
			var next: Vector2i = current + direction
			if map_data.is_valid(next) and visited[map_data.index(next)] == 0 and (air or map_data.is_traversable_ground(next)):
				visited[map_data.index(next)] = 1; previous[next] = current; queue.append(next)
				if next == destination:
					var reversed: Array[Vector2i] = [destination]; var step := destination
					while step != start: step = previous[step]; reversed.append(step)
					reversed.reverse(); return reversed
	return []

func tick() -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	damaged_structure_tiles.clear()
	run_ai()
	for unit_id in sorted_unit_ids():
		if units.has(unit_id): units[unit_id]["weapon_cooldown"] = maxi(0, int(units[unit_id].get("weapon_cooldown", 0)) - 1)
		if units.has(unit_id) and bool(units[unit_id]["alive"]): update_unit(unit_id)
	for unit_id in sorted_unit_ids():
		if units.has(unit_id) and bool(units[unit_id]["alive"]): changed.append_array(capture_from_unit(unit_id))
	return changed

func update_unit(unit_id: int) -> void:
	var unit: Dictionary = units[unit_id]
	var command: int = int(unit["command"])
	if command == CombatConfigScript.COMMAND_ATTACK:
		if int(unit["type"]) == 3 and unit.has("target_tile"):
			if int(unit["weapon_cooldown"]) == 0:
				artillery_impact(unit_id, unit["target_tile"])
				unit["weapon_cooldown"] = CombatConfigScript.ARTILLERY_COOLDOWN_TICKS
				unit.erase("target_tile")
				unit["command"] = CombatConfigScript.COMMAND_STOP
			return
		var target := get_unit(int(unit["target_id"]))
		if target.is_empty() or not bool(target["alive"]): unit["command"] = CombatConfigScript.COMMAND_IDLE; return
		if in_range(unit, target["tile"]): apply_attack(unit_id, int(target["id"]))
		else: move_toward_target(unit_id, target["tile"])
	elif command == CombatConfigScript.COMMAND_DEFEND:
		var target_id := nearest_enemy_in_range(unit, int(unit["type"]) == 3)
		if target_id >= 0: apply_attack(unit_id, target_id)
	elif command == CombatConfigScript.COMMAND_MOVE:
		move_along_path(unit_id)

func move_toward_target(unit_id: int, destination: Vector2i) -> void:
	var unit: Dictionary = units[unit_id]
	var path: Array = unit["path"]
	if path.is_empty() or path.back() != destination:
		path = find_path(unit["tile"], destination, bool(unit["air"]))
		if path.is_empty(): unit["command"] = CombatConfigScript.COMMAND_IDLE; return
		unit["path"] = path; unit["path_index"] = 1; unit["move_wait"] = 0; path_rebuild_count += 1
	move_along_path(unit_id)

func move_along_path(unit_id: int) -> void:
	var unit: Dictionary = units[unit_id]; var path: Array = unit["path"]; var path_index: int = int(unit["path_index"])
	if path_index >= path.size(): unit["command"] = CombatConfigScript.COMMAND_IDLE; return
	var next: Vector2i = path[path_index]
	if not bool(unit["air"]) and not map_data.is_traversable_ground(next): unit["command"] = CombatConfigScript.COMMAND_IDLE; return
	if int(unit["move_wait"]) > 0: unit["move_wait"] = int(unit["move_wait"]) - 1; return
	unit["tile"] = next; unit["world_position"] = next; unit["path_index"] = path_index + 1
	unit["move_wait"] = 0 if bool(unit["air"]) else CombatConfigScript.terrain_move_cost(map_data.get_terrain(next)) - 1
	if int(unit["path_index"]) >= path.size(): unit["command"] = CombatConfigScript.COMMAND_IDLE

func apply_attack(attacker_id: int, target_id: int) -> void:
	var attacker := get_unit(attacker_id); var target := get_unit(target_id)
	if attacker.is_empty() or target.is_empty() or not bool(attacker["alive"]) or not bool(target["alive"]) or not in_range(attacker, target["tile"]): return
	if int(attacker["type"]) == 3:
		if not can_artillery_hit(attacker, target["tile"]): return
		artillery_impact(attacker_id, target["tile"])
		attacker["weapon_cooldown"] = CombatConfigScript.ARTILLERY_COOLDOWN_TICKS
		return
	var multiplier := 1.0 if bool(target["air"]) else CombatConfigScript.defense_multiplier(map_data.get_terrain(target["tile"]))
	var amount := maxf(1.0, float(attacker["damage"]) - float(target["armor"])) * multiplier
	target["health"] = maxf(0.0, float(target["health"]) - amount)
	if float(target["health"]) <= 0.0:
		target["alive"] = false; target["command"] = CombatConfigScript.COMMAND_STOP; target["path"] = []
		if selected_unit_id == target_id: selected_unit_id = -1

func in_range(unit: Dictionary, tile: Vector2i) -> bool:
	return Vector2i(unit["tile"]).distance_squared_to(tile) <= int(unit["range"]) * int(unit["range"])

func nearest_enemy_in_range(unit: Dictionary, artillery: bool = false) -> int:
	for candidate_id in sorted_unit_ids():
		var candidate: Dictionary = units[candidate_id]
		if bool(candidate["alive"]) and int(candidate["owner"]) != int(unit["owner"]) and (can_artillery_hit(unit, candidate["tile"]) if artillery else in_range(unit, candidate["tile"])): return candidate_id
	return -1

func can_artillery_hit(unit: Dictionary, tile: Vector2i) -> bool:
	var distance := Vector2i(unit["tile"]).distance_to(tile)
	return distance >= CombatConfigScript.ARTILLERY_MIN_RANGE and distance <= CombatConfigScript.ARTILLERY_MAX_RANGE and int(unit.get("weapon_cooldown", 0)) == 0

func artillery_impact(attacker_id: int, center: Vector2i) -> void:
	var attacker := get_unit(attacker_id)
	for candidate_id in sorted_unit_ids():
		var target := get_unit(candidate_id)
		if not target.is_empty() and bool(target["alive"]) and Vector2i(target["tile"]).distance_to(center) <= CombatConfigScript.ARTILLERY_SPLASH_RADIUS:
			var amount := maxf(1.0, float(attacker["damage"]) - float(target["armor"]))
			target["health"] = maxf(0.0, float(target["health"]) - amount)
			if float(target["health"]) <= 0.0: target["alive"] = false
	for y in range(center.y - CombatConfigScript.ARTILLERY_SPLASH_RADIUS, center.y + CombatConfigScript.ARTILLERY_SPLASH_RADIUS + 1):
		for x in range(center.x - CombatConfigScript.ARTILLERY_SPLASH_RADIUS, center.x + CombatConfigScript.ARTILLERY_SPLASH_RADIUS + 1):
			var tile := Vector2i(x, y)
			if map_data.is_valid(tile) and tile.distance_to(center) <= CombatConfigScript.ARTILLERY_SPLASH_RADIUS:
				var target_city = ai_city_data if int(attacker.get("owner", CombatConfigScript.OWNER_PLAYER)) == CombatConfigScript.OWNER_PLAYER else city_data
				if target_city != null and target_city.destroy_structure(tile): damaged_structure_tiles.append(tile)

func capture_from_unit(unit_id: int) -> Array[Vector2i]:
	var unit: Dictionary = units[unit_id]; var changed: Array[Vector2i] = []
	if bool(unit["air"]) or not map_data.is_traversable_ground(unit["tile"]): return changed
	var progress: int = int(terrain_capture_progress.get(unit_id, 0)) + 1; terrain_capture_progress[unit_id] = progress
	if progress >= CombatConfigScript.CAPTURE_TICKS:
		terrain_capture_progress[unit_id] = 0
		for y in range(unit["tile"].y - CombatConfigScript.CAPTURE_RADIUS, unit["tile"].y + CombatConfigScript.CAPTURE_RADIUS + 1):
			for x in range(unit["tile"].x - CombatConfigScript.CAPTURE_RADIUS, unit["tile"].x + CombatConfigScript.CAPTURE_RADIUS + 1):
				var tile := Vector2i(x, y)
				if map_data.is_traversable_ground(tile) and territory[map_data.index(tile)] != int(unit["owner"]): territory[map_data.index(tile)] = int(unit["owner"]); changed.append(tile); terrain_visual_changes += 1
	update_capital_capture(unit)
	return changed

func update_capital_capture(unit: Dictionary) -> void:
	var tile: Vector2i = unit["tile"]
	var owner: int = int(unit["owner"])
	var target_name := ""
	if tile == map_data.ai_capital and owner == CombatConfigScript.OWNER_PLAYER and ai_capital_owner != owner: target_name = "ai"
	elif tile == map_data.player_capital and owner == CombatConfigScript.OWNER_AI and player_capital_owner != owner: target_name = "player"
	if target_name.is_empty(): return
	var key := "%s:%d" % [target_name, int(unit["id"])]
	var progress: int = int(capital_progress.get(key, 0)) + 1; capital_progress[key] = progress
	if progress >= CombatConfigScript.CAPITAL_CAPTURE_TICKS:
		if target_name == "ai": ai_capital_owner = owner; status_message = "AI CAPITAL CAPTURED"
		else: player_capital_owner = owner; status_message = "PLAYER CAPITAL CAPTURED"

func run_ai() -> void:
	for unit_id in sorted_unit_ids():
		var unit: Dictionary = units[unit_id]
		if not bool(unit["alive"]) or int(unit["owner"]) != CombatConfigScript.OWNER_AI: continue
		var nearby := nearest_enemy_in_range(unit)
		if nearby >= 0: issue_attack(unit_id, nearby)
		elif int(unit["command"]) == CombatConfigScript.COMMAND_IDLE and not bool(unit.get("strategic_managed", false)): issue_move(unit_id, map_data.player_capital)

func spawn_developer_ai_force() -> bool:
	if units.size() > 0: return reject("Developer combat setup already active")
	var tiles := [map_data.ai_capital, map_data.ai_capital + Vector2i(1, 0), map_data.ai_capital + Vector2i(0, 1)]
	for i in tiles.size():
		if valid_deployment_tile(i + 1, tiles[i]): create_unit(CombatConfigScript.OWNER_AI, i + 1, tiles[i])
	return accept("Developer AI force deployed")

func selected_summary() -> String:
	var unit := get_unit(selected_unit_id)
	if unit.is_empty() or not bool(unit["alive"]): return ""
	return "Unit: %s  %s  HP %.0f/%.0f  %s" % [CombatConfigScript.UNIT_DATA[int(unit["type"])]["name"], "Player" if int(unit["owner"]) == 1 else "AI", float(unit["health"]), float(unit["max_health"]), CombatConfigScript.command_name(int(unit["command"]))]

func sorted_unit_ids() -> Array:
	var ids: Array = units.keys(); ids.sort(); return ids

func accept(message: String) -> bool: last_action_reason = message; return true
func reject(message: String) -> bool: last_action_reason = message; return false
