class_name SaveValidator
extends RefCounted

# Validate serialized values before casting or allocating simulation objects.
# JSON numbers arrive as floats, so integer fields must be integral as well.
const MAX_COUNTER := 2147483647
const MAX_VALUE := 1.0e15
const MAX_MAP_SIDE := 1024
const MAX_TILES := 1048576
const CityConfigScript = preload("res://scripts/city_config.gd")

var error := ""
var size := Vector2i.ZERO
var tile_count := 0

func validate(document: Variant) -> String:
	error = ""
	if not document is Dictionary:
		return "Invalid save root"
	if not integer(document.get("version"), 1, MAX_COUNTER):
		return "Invalid save version"
	if int(document.version) != 1:
		return "Unsupported save version %d (expected 1)" % int(document.version)
	for name in ["map", "city", "combat", "strategic", "campaign"]:
		if not document.get(name) is Dictionary:
			return "Save section is missing or invalid: %s" % name
	if not map_section(document.map):
		return "Invalid map: " + error
	if not city_section(document.city):
		return "Invalid city: " + error
	if not combat_section(document.combat):
		return "Invalid combat: " + error
	if not strategic_section(document.strategic):
		return "Invalid strategic: " + error
	if document.has("ai"):
		if not document.ai is Dictionary or not ai_section(document.ai):
			return "Invalid AI: " + error
	if not campaign_section(document.campaign):
		return "Invalid campaign: " + error
	var metadata: Variant = document.get("metadata", {})
	if not metadata is Dictionary or not text(metadata.get("kind", "manual")) or not integer(metadata.get("autosave_sequence", -1), -1, MAX_COUNTER - 1):
		return "Invalid save metadata"
	return ""

func number(value: Variant, minimum: float = 0.0, maximum: float = MAX_VALUE) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func integer(value: Variant, minimum: int = 0, maximum: int = MAX_COUNTER) -> bool:
	return number(value, minimum, maximum) and float(value) == floorf(float(value))

func text(value: Variant) -> bool:
	return value is String and value.length() <= 4096

func reject(field: String) -> bool:
	error = field
	return false

func fields(record: Dictionary, names: Array, integral: bool = true, minimum: float = 0.0, maximum: float = MAX_COUNTER) -> bool:
	for name in names:
		var value: Variant = record.get(name, 0)
		if not (integer(value, int(minimum), int(maximum)) if integral else number(value, minimum, maximum)):
			return reject(String(name))
	return true

func array_numbers(value: Variant, count: int, maximum: float, integral: bool = true) -> bool:
	if not value is Array or value.size() != count:
		return false
	for element in value:
		if not (integer(element, 0, int(maximum)) if integral else number(element, 0.0, maximum)):
			return false
	return true

func tile(value: Variant, allow_unset: bool = false) -> bool:
	if not value is Array or value.size() != 2:
		return false
	if allow_unset and integer(value[0], -1, -1) and integer(value[1], -1, -1):
		return true
	return integer(value[0], 0, size.x - 1) and integer(value[1], 0, size.y - 1)

func tiles(value: Variant) -> bool:
	if not value is Array or value.size() > tile_count:
		return false
	for position in value:
		if not tile(position):
			return false
	return true

func map_section(record: Dictionary) -> bool:
	var dimensions: Variant = record.get("size")
	if not dimensions is Array or dimensions.size() != 2 or not integer(dimensions[0], 1, MAX_MAP_SIDE) or not integer(dimensions[1], 1, MAX_MAP_SIDE):
		return reject("dimensions")
	size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	tile_count = size.x * size.y
	if tile_count > MAX_TILES or not number(record.get("seed", 0), -MAX_VALUE, MAX_VALUE) or float(record.get("seed", 0)) != floorf(float(record.get("seed", 0))):
		return reject("dimensions or seed")
	for name in {"terrain": 4, "bridges": 1, "deposits": 3, "markers": 1, "scorched": 1}:
		var maximum: int = {"terrain": 4, "bridges": 1, "deposits": 3, "markers": 1, "scorched": 1}[name]
		if not array_numbers(record.get(name), tile_count, maximum):
			return reject(name)
	if not tile(record.get("player_capital")) or not tile(record.get("ai_capital")):
		return reject("capital position")
	return true

func city_section(record: Dictionary) -> bool:
	for name in {"roads": 1, "zones": 2, "buildings": 18, "rubble": 1}:
		var maximum: int = {"roads": 1, "zones": 2, "buildings": 18, "rubble": 1}[name]
		if not array_numbers(record.get(name), tile_count, maximum):
			return reject(name)
	if not array_numbers(record.get("resources"), 7, MAX_VALUE, false) or not array_numbers(record.get("completed_technologies"), 8, 1) or not array_numbers(record.get("produced_units"), 8, MAX_COUNTER):
		return reject("ledger or progression")
	if not fields(record, ["household_capacity", "occupied_households", "job_capacity", "employed_workforce", "tick_count", "operation_workforce_remaining"]):
		return false
	if not fields(record, ["research_progress", "operation_power_remaining"], false, 0.0, MAX_VALUE) or not integer(record.get("active_technology", 0), 0, 7) or not integer(record.get("selected_import_resource", 3), 3, 6) or not text(record.get("research_status", "")):
		return reject("research or operation values")
	if not tiles(record.get("industry_buildings", [])):
		return reject("industry positions")
	var orders: Variant = record.get("import_orders", [])
	if not orders is Array or orders.size() > tile_count:
		return reject("import orders")
	for order in orders:
		if not order is Dictionary or not integer(order.get("resource"), 3, 6) or not number(order.get("quantity"), 0.000001) or not number(order.get("cost")) or not integer(order.get("remaining"), 1):
			return reject("import order values")
	orders = record.get("manufacturing_orders", [])
	if not orders is Array or orders.size() > tile_count:
		return reject("manufacturing orders")
	var facilities := {}
	for order in orders:
		if not order is Dictionary or not tile(order.get("tile")) or not integer(order.get("unit"), 1, 7) or not integer(order.get("remaining")):
			return reject("manufacturing order values")
		var position: Array = order.tile
		var index := int(position[1]) * size.x + int(position[0])
		if facilities.has(index) or int(record.buildings[index]) != int(CityConfigScript.UNIT_DATA[int(order.unit)].facility):
			return reject("manufacturing facility")
		facilities[index] = true
	return true

func combat_section(record: Dictionary) -> bool:
	if not array_numbers(record.get("territory"), tile_count, 2) or not integer(record.get("ai_capital_owner", 2), 1, 2) or not integer(record.get("player_capital_owner", 1), 1, 2):
		return reject("ownership")
	var units: Variant = record.get("units", [])
	if not units is Array or units.size() > tile_count:
		return reject("units")
	var ids := {}
	var highest_id := 0
	for unit in units:
		if not unit is Dictionary or not integer(unit.get("id"), 1) or ids.has(int(unit.id)):
			return reject("unit id")
		ids[int(unit.id)] = true
		highest_id = maxi(highest_id, int(unit.id))
		if not integer(unit.get("owner"), 1, 2) or not integer(unit.get("type"), 1, 7) or not integer(unit.get("command"), 0, 4) or not integer(unit.get("target_id", -1), -1):
			return reject("unit enums")
		for name in ["tile", "world_position", "defend_tile"]:
			if not tile(unit.get(name)):
				return reject("unit " + name)
		if unit.has("target_tile") and not tile(unit.target_tile):
			return reject("unit target position")
		if not tiles(unit.get("path", [])) or not fields(unit, ["path_index", "move_wait", "weapon_cooldown", "range"]):
			return reject("unit path or counters")
		if not unit.get("path", []).is_empty() and int(unit.get("path_index", 0)) > unit.path.size():
			return reject("unit path index")
		if not fields(unit, ["health", "armor", "damage"], false, 0.0, MAX_VALUE) or not number(unit.get("max_health"), 0.000001) or not number(unit.get("movement_speed"), 0.000001) or float(unit.get("health", 0)) > float(unit.max_health):
			return reject("unit stats")
		for name in ["air", "alive"]:
			if typeof(unit.get(name)) != TYPE_BOOL:
				return reject("unit " + name)
		if unit.has("strategic_managed") and typeof(unit.strategic_managed) != TYPE_BOOL:
			return reject("unit management")
	if not integer(record.get("next_unit_id", 1), highest_id + 1):
		return reject("next unit id")
	for unit in units:
		if int(unit.get("target_id", -1)) != -1 and not ids.has(int(unit.target_id)):
			return reject("unit target id")
	for name in ["capital_progress", "terrain_capture_progress"]:
		var entries: Variant = record.get(name, [])
		if not entries is Array or entries.size() > units.size() * 2:
			return reject(name)
		var keys := {}
		for entry in entries:
			if not entry is Dictionary or not integer(entry.get("value")):
				return reject(name)
			var key: Variant = entry.get("key")
			if name == "capital_progress":
				if not key is String or key.get_slice_count(":") != 2 or key.get_slice(":", 0) not in ["ai", "player"] or not key.get_slice(":", 1).is_valid_int() or not ids.has(key.get_slice(":", 1).to_int()):
					return reject(name)
			else:
				if not integer(key, 1) or not ids.has(int(key)):
					return reject(name)
			if keys.has(key):
				return reject("duplicate " + name)
			keys[key] = true
	return true

func strategic_section(record: Dictionary) -> bool:
	if not fields(record, ["tick_count"]):
		return false
	for name in ["silos", "sam_cooldowns", "missiles"]:
		if not record.get(name, []) is Array or record.get(name, []).size() > tile_count:
			return reject(name)
	var positions := {}
	for silo in record.get("silos", []):
		if not silo is Dictionary or not tile(silo.get("tile")) or not integer(silo.get("stored"), 0, 3) or not integer(silo.get("production"), 0, 3) or not integer(silo.get("cooldown")):
			return reject("silo values")
		if positions.has(str(silo.tile)):
			return reject("duplicate silo")
		positions[str(silo.tile)] = true
	positions.clear()
	for sam in record.get("sam_cooldowns", []):
		if not sam is Dictionary or not tile(sam.get("tile")) or not integer(sam.get("value")):
			return reject("SAM values")
		if positions.has(str(sam.tile)):
			return reject("duplicate SAM")
		positions[str(sam.tile)] = true
	var ids := {}
	var highest_id := 0
	for missile in record.get("missiles", []):
		if not missile is Dictionary or not integer(missile.get("id"), 1) or ids.has(int(missile.id)) or not integer(missile.get("owner"), 1, 2):
			return reject("missile id or owner")
		ids[int(missile.id)] = true
		highest_id = maxi(highest_id, int(missile.id))
		if not tile(missile.get("source")) or not tile(missile.get("target")) or not integer(missile.get("duration"), 1) or not integer(missile.get("elapsed")) or not number(missile.get("progress"), 0.0, 1.0):
			return reject("missile flight")
		if int(missile.elapsed) > int(missile.duration) or typeof(missile.get("alive")) != TYPE_BOOL or typeof(missile.get("intercepted")) != TYPE_BOOL:
			return reject("missile state")
	if not integer(record.get("next_missile_id", 1), highest_id + 1):
		return reject("next missile id")
	return true

func ai_section(record: Dictionary) -> bool:
	if not record.get("economy") is Dictionary or not city_section(record.economy):
		return reject("economy " + error)
	if not integer(record.get("phase", 0), 0, 4) or not fields(record, ["simulation_ticks", "decision_count"]) or not text(record.get("last_decision", "")):
		return reject("policy values")
	if not tiles(record.get("road_plan", [])) or not tiles(record.get("building_sites", [])) or not tile(record.get("current_target", [-1, -1]), true):
		return reject("policy positions")
	if not integer(record.get("road_cursor", 0), 0, record.get("road_plan", []).size()) or not integer(record.get("site_cursor", 0), 0, record.get("building_sites", []).size()):
		return reject("policy cursor")
	return true

func campaign_section(record: Dictionary) -> bool:
	if not integer(record.get("phase"), 0, 3) or not fields(record, ["elapsed_ticks", "victory_event_count", "defeat_event_count"]) or not text(record.get("defeated_nation", "")) or not tile(record.get("defeated_capital", [-1, -1]), true):
		return reject("outcome values")
	var stats: Variant = record.get("victory_stats", {})
	if not stats is Dictionary or stats.size() > 32:
		return reject("outcome stats")
	for name in stats:
		if not name is String or not number(stats[name]):
			return reject("outcome stats")
	return true
