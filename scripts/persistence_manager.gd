class_name PersistenceManager
extends RefCounted

const MapDataScript = preload("res://scripts/map_data.gd")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CityConfigScript = preload("res://scripts/city_config.gd")
const CombatSimulationScript = preload("res://scripts/combat_simulation.gd")
const StrategicSimulationScript = preload("res://scripts/strategic_simulation.gd")
const CampaignStateScript = preload("res://scripts/campaign_state.gd")
const AICampaignControllerScript = preload("res://scripts/ai_campaign_controller.gd")

const SaveValidatorScript = preload("res://scripts/save_validator.gd")

const MAX_SAVE_BYTES := 16 * 1024 * 1024
const SAVE_VERSION := 1
const SAVE_DIRECTORY := "user://saves"
const MANUAL_SAVE_PATH := SAVE_DIRECTORY + "/manual_save.json"
const AUTOSAVE_SLOTS := 3
const AUTOSAVE_INTERVAL_SECONDS := 120.0

var autosave_slot := 0
var autosave_sequence := 0
var manual_save_path := MANUAL_SAVE_PATH
var autosave_directory := SAVE_DIRECTORY
var last_error := ""
var last_save_duration_msec := 0.0
var last_load_duration_msec := 0.0
var last_load_used_backup := false
var last_save_size_bytes := 0

func create_save_data(map_data, city, combat, strategic, campaign, kind: String = "manual", sequence: int = -1, ai_campaign = null) -> Dictionary:
	var document := {
		"version": SAVE_VERSION,
		"metadata": {"kind": kind, "autosave_sequence": sequence},
		"map": serialize_map(map_data),
		"city": serialize_city(city),
		"combat": serialize_combat(combat),
		"strategic": serialize_strategic(strategic),
		"campaign": serialize_campaign(campaign),
	}
	if ai_campaign != null:
		document["ai"] = serialize_ai(ai_campaign)
	return document

func save_game(path: String, map_data, city, combat, strategic, campaign, kind: String = "manual", sequence: int = -1, ai_campaign = null) -> bool:
	var started := Time.get_ticks_usec()
	last_error = ""
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return fail_save(started, "Cannot create save directory (%d)" % directory_error)
	if DirAccess.dir_exists_absolute(absolute_path):
		return fail_save(started, "Save destination is a directory")
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".backup"
	remove_if_present(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return fail_save(started, "Cannot open temporary save file (%d)" % FileAccess.get_open_error())
	file.store_string(JSON.stringify(create_save_data(map_data, city, combat, strategic, campaign, kind, sequence, ai_campaign)))
	file.flush()
	last_save_size_bytes = file.get_length()
	file.close()
	var verification := parse_document(temporary_path)
	if verification.is_empty():
		remove_if_present(temporary_path)
		return fail_save(started, "Temporary save verification failed: %s" % last_error)
	# Keep a valid interrupted-write backup until replacement succeeds.
	# A corrupt primary must never replace that known-good recovery file.
	var had_previous := FileAccess.file_exists(absolute_path)
	var moved_previous := had_previous and not parse_document(absolute_path).is_empty()
	if moved_previous:
		remove_if_present(backup_path)
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			remove_if_present(temporary_path)
			return fail_save(started, "Cannot preserve previous save (%d)" % backup_error)
	var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK:
		if moved_previous:
			DirAccess.rename_absolute(backup_path, absolute_path)
		remove_if_present(temporary_path)
		return fail_save(started, "Cannot replace save file (%d)" % replace_error)
	remove_if_present(backup_path)
	last_error = ""
	last_save_duration_msec = float(Time.get_ticks_usec() - started) / 1000.0
	return true

func save_autosave(map_data, city, combat, strategic, campaign, directory: String = "", ai_campaign = null) -> bool:
	var target_directory := autosave_directory if directory.is_empty() else directory
	var path := autosave_path(autosave_slot, target_directory)
	if not save_game(path, map_data, city, combat, strategic, campaign, "autosave", autosave_sequence, ai_campaign):
		return false
	autosave_slot = (autosave_slot + 1) % AUTOSAVE_SLOTS
	autosave_sequence += 1
	return true

func configure_autosave_rotation(directory: String = "") -> void:
	var target_directory := autosave_directory if directory.is_empty() else directory
	var highest_sequence := -1
	for slot in AUTOSAVE_SLOTS:
		var path := autosave_path(slot, target_directory)
		if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".backup"):
			continue
		var document := read_recoverable_document(path)
		if not document.is_empty():
			highest_sequence = maxi(highest_sequence, int(Dictionary(document.get("metadata", {})).get("autosave_sequence", -1)))
	autosave_sequence = highest_sequence + 1
	autosave_slot = autosave_sequence % AUTOSAVE_SLOTS
	last_error = ""

func autosave_path(slot: int, directory: String = "") -> String:
	var target_directory := autosave_directory if directory.is_empty() else directory
	return "%s/autosave_%d.json" % [target_directory, posmod(slot, AUTOSAVE_SLOTS)]

func latest_autosave_path(directory: String = "") -> String:
	var target_directory := autosave_directory if directory.is_empty() else directory
	var highest_sequence := -1
	var latest_path := ""
	for slot in AUTOSAVE_SLOTS:
		var path := autosave_path(slot, target_directory)
		if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".backup"):
			continue
		var document := read_recoverable_document(path)
		if document.is_empty():
			continue
		var sequence := int(Dictionary(document.get("metadata", {})).get("autosave_sequence", -1))
		if sequence > highest_sequence:
			highest_sequence = sequence
			latest_path = path
	last_error = "" if not latest_path.is_empty() else "No autosave found"
	return latest_path

func load_game(path: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	last_error = ""
	var document := read_recoverable_document(ProjectSettings.globalize_path(path))
	if document.is_empty():
		last_load_duration_msec = float(Time.get_ticks_usec() - started) / 1000.0
		return {}
	var result := reconstruct_validated(document)
	last_load_duration_msec = float(Time.get_ticks_usec() - started) / 1000.0
	return result

func read_recoverable_document(path: String) -> Dictionary:
	last_load_used_backup = false
	var document := parse_document(path)
	if not document.is_empty():
		return document
	var primary_error := last_error
	if FileAccess.file_exists(path + ".backup"):
		document = parse_document(path + ".backup")
		if not document.is_empty():
			last_load_used_backup = true
			last_error = ""
			return document
	last_error = primary_error
	return {}

func parse_document(path: String) -> Dictionary:
	last_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fail_load("Save file not found or unreadable")
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return fail_load("Save file exceeds the 16 MiB limit")
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(contents) != OK:
		return fail_load("Invalid save data at line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	var validation_error: String = SaveValidatorScript.new().validate(parser.data)
	if not validation_error.is_empty():
		return fail_load(validation_error)
	return parser.data

func reconstruct(document: Dictionary) -> Dictionary:
	last_error = SaveValidatorScript.new().validate(document)
	if not last_error.is_empty():
		return {}
	return reconstruct_validated(document)

func reconstruct_validated(document: Dictionary) -> Dictionary:
	var map_section: Dictionary = document["map"]
	var size := decode_vector(map_section.get("size", []))
	if size.x <= 0 or size.y <= 0 or size.x * size.y > 1048576:
		return fail_load("Invalid map dimensions")
	var tile_count := size.x * size.y
	for key in ["terrain", "bridges", "deposits", "markers", "scorched"]:
		if not valid_array(map_section.get(key), tile_count):
			return fail_load("Invalid map layer: %s" % key)
	var map_data = MapDataScript.new(size, int(map_section.get("seed", 0)), false)
	map_data.terrain = decode_bytes(map_section["terrain"])
	map_data.bridges = decode_bytes(map_section["bridges"])
	map_data.deposits = decode_bytes(map_section["deposits"])
	map_data.markers = decode_bytes(map_section["markers"])
	map_data.scorched = decode_bytes(map_section["scorched"])
	map_data.player_capital = decode_vector(map_section.get("player_capital", []))
	map_data.ai_capital = decode_vector(map_section.get("ai_capital", []))
	if not map_data.is_valid(map_data.player_capital) or not map_data.is_valid(map_data.ai_capital):
		return fail_load("Invalid capital position")

	var city_section: Dictionary = document["city"]
	for key in ["roads", "zones", "buildings", "rubble"]:
		if not valid_array(city_section.get(key), tile_count):
			return fail_load("Invalid city layer: %s" % key)
	if not valid_array(city_section.get("resources"), 7) or not valid_array(city_section.get("completed_technologies"), CityConfigScript.TECH_COUNT) or not valid_array(city_section.get("produced_units"), CityConfigScript.UNIT_COUNT):
		return fail_load("Invalid city ledger or progression layer")
	var city = CitySimulationScript.new(map_data)
	city.roads = decode_bytes(city_section["roads"])
	city.zones = decode_bytes(city_section["zones"])
	city.buildings = decode_bytes(city_section["buildings"])
	city.rubble = decode_bytes(city_section["rubble"])
	city.resources = decode_floats(city_section["resources"])
	city.completed_technologies = decode_bytes(city_section["completed_technologies"])
	city.produced_units = decode_ints(city_section["produced_units"])
	city.household_capacity = int(city_section.get("household_capacity", 0))
	city.occupied_households = int(city_section.get("occupied_households", 0))
	city.job_capacity = int(city_section.get("job_capacity", 0))
	city.employed_workforce = int(city_section.get("employed_workforce", 0))
	city.tick_count = int(city_section.get("tick_count", 0))
	city.active_technology = int(city_section.get("active_technology", 0))
	city.research_progress = float(city_section.get("research_progress", 0.0))
	city.research_status = String(city_section.get("research_status", "No active research"))
	city.selected_import_resource = int(city_section.get("selected_import_resource", CitySimulationScript.LedgerResource.FOOD))
	city.operation_workforce_remaining = int(city_section.get("operation_workforce_remaining", 0))
	city.operation_power_remaining = float(city_section.get("operation_power_remaining", 0.0))
	city.industry_buildings = decode_tile_list(city_section.get("industry_buildings", []), map_data)
	if city.industry_buildings.size() != Array(city_section.get("industry_buildings", [])).size():
		return fail_load("Invalid industry building position")
	city.import_orders = decode_import_orders(city_section.get("import_orders", []))
	if city.import_orders.size() != Array(city_section.get("import_orders", [])).size():
		return fail_load("Invalid import order")
	city.manufacturing_orders = decode_manufacturing_orders(city_section.get("manufacturing_orders", []), map_data)
	if city.manufacturing_orders.size() != Array(city_section.get("manufacturing_orders", [])).size():
		return fail_load("Invalid manufacturing order")
	city.rebuild_coverage()

	var combat_section: Dictionary = document["combat"]
	if not valid_array(combat_section.get("territory"), tile_count):
		return fail_load("Invalid territory layer")
	var combat = CombatSimulationScript.new(map_data, city)
	combat.territory = decode_bytes(combat_section["territory"])
	combat.next_unit_id = int(combat_section.get("next_unit_id", 1))
	combat.ai_capital_owner = int(combat_section.get("ai_capital_owner", 2))
	combat.player_capital_owner = int(combat_section.get("player_capital_owner", 1))
	combat.capital_progress = decode_string_int_entries(combat_section.get("capital_progress", []))
	combat.terrain_capture_progress = decode_int_int_entries(combat_section.get("terrain_capture_progress", []))
	var decoded_units := decode_units(combat_section.get("units", []), map_data)
	if decoded_units.is_empty() and not Array(combat_section.get("units", [])).is_empty():
		return fail_load("Invalid combat unit data")
	combat.units = decoded_units
	combat.clear_selection()

	var strategic_section: Dictionary = document["strategic"]
	var strategic = StrategicSimulationScript.new(map_data, city, combat)
	strategic.tick_count = int(strategic_section.get("tick_count", 0))
	strategic.next_missile_id = int(strategic_section.get("next_missile_id", 1))
	strategic.silos = decode_tile_state_entries(strategic_section.get("silos", []), map_data, ["stored", "cooldown", "production"])
	strategic.sam_cooldowns = decode_tile_values(strategic_section.get("sam_cooldowns", []), map_data)
	strategic.missiles = decode_missiles(strategic_section.get("missiles", []), map_data)
	if strategic.silos.is_empty() and not Array(strategic_section.get("silos", [])).is_empty():
		return fail_load("Invalid silo data")
	if strategic.sam_cooldowns.is_empty() and not Array(strategic_section.get("sam_cooldowns", [])).is_empty():
		return fail_load("Invalid SAM data")
	if strategic.missiles.is_empty() and not Array(strategic_section.get("missiles", [])).is_empty():
		return fail_load("Invalid missile data")
	strategic.selected_silo = Vector2i(-1, -1)
	var ai_campaign = AICampaignControllerScript.new(map_data, city, combat, strategic)
	if typeof(document.get("ai")) == TYPE_DICTIONARY:
		var ai_section: Dictionary = document["ai"]
		if typeof(ai_section.get("economy")) != TYPE_DICTIONARY:
			return fail_load("Invalid AI economy section")
		var ai_city = deserialize_city(Dictionary(ai_section["economy"]), map_data)
		if ai_city == null:
			return fail_load("Invalid AI economy data")
		ai_campaign.economy = ai_city
		ai_campaign.phase = int(ai_section.get("phase", AICampaignControllerScript.Phase.BUILD))
		ai_campaign.simulation_ticks = int(ai_section.get("simulation_ticks", 0))
		ai_campaign.decision_count = int(ai_section.get("decision_count", 0))
		ai_campaign.road_cursor = int(ai_section.get("road_cursor", 0))
		ai_campaign.site_cursor = int(ai_section.get("site_cursor", 0))
		ai_campaign.road_plan = decode_tile_list(ai_section.get("road_plan", []), map_data)
		ai_campaign.building_sites = decode_tile_list(ai_section.get("building_sites", []), map_data)
		ai_campaign.current_target = decode_vector(ai_section.get("current_target", [-1, -1]))
		ai_campaign.last_decision = String(ai_section.get("last_decision", "Loaded"))
	ai_campaign.configure(city, combat, strategic)
	if document.has("ai"):
		# Earlier schema-v1 saves omitted this per-unit policy marker. Restore
		# campaign ownership so idle defenders do not become tactical attackers.
		for unit in combat.units.values():
			if int(unit["owner"]) == 2 and not unit.has("strategic_managed"):
				unit["strategic_managed"] = true

	var campaign_section: Dictionary = document["campaign"]
	var phase := int(campaign_section.get("phase", -1))
	if phase < CampaignStateScript.Phase.ACTIVE or phase > CampaignStateScript.Phase.PLAYER_DEFEAT:
		return fail_load("Invalid campaign phase")
	var campaign = CampaignStateScript.new()
	campaign.phase = phase
	campaign.elapsed_ticks = int(campaign_section.get("elapsed_ticks", 0))
	campaign.victory_event_count = int(campaign_section.get("victory_event_count", 0))
	campaign.defeat_event_count = int(campaign_section.get("defeat_event_count", 0))
	campaign.defeated_nation = String(campaign_section.get("defeated_nation", ""))
	campaign.defeated_capital = decode_vector(campaign_section.get("defeated_capital", [-1, -1]))
	campaign.victory_stats = Dictionary(campaign_section.get("victory_stats", {})).duplicate(true)

	return {"map": map_data, "city": city, "combat": combat, "strategic": strategic, "campaign": campaign, "ai_campaign": ai_campaign, "metadata": document.get("metadata", {})}

func serialize_map(map_data) -> Dictionary:
	return {"size": encode_vector(map_data.size), "seed": map_data.seed, "terrain": encode_packed(map_data.terrain), "bridges": encode_packed(map_data.bridges), "deposits": encode_packed(map_data.deposits), "markers": encode_packed(map_data.markers), "scorched": encode_packed(map_data.scorched), "player_capital": encode_vector(map_data.player_capital), "ai_capital": encode_vector(map_data.ai_capital)}

func serialize_city(city) -> Dictionary:
	var imports: Array = []
	for entry in city.import_orders:
		imports.append({"resource": int(entry["resource"]), "quantity": float(entry["quantity"]), "cost": float(entry["cost"]), "remaining": int(entry["remaining"])})
	var manufacturing: Array = []
	for entry in city.manufacturing_orders:
		manufacturing.append({"tile": encode_vector(entry["tile"]), "unit": int(entry["unit"]), "remaining": int(entry["remaining"])})
	return {"roads": encode_packed(city.roads), "zones": encode_packed(city.zones), "buildings": encode_packed(city.buildings), "rubble": encode_packed(city.rubble), "resources": encode_packed(city.resources), "completed_technologies": encode_packed(city.completed_technologies), "produced_units": encode_packed(city.produced_units), "household_capacity": city.household_capacity, "occupied_households": city.occupied_households, "job_capacity": city.job_capacity, "employed_workforce": city.employed_workforce, "operation_workforce_remaining": city.operation_workforce_remaining, "operation_power_remaining": city.operation_power_remaining, "tick_count": city.tick_count, "industry_buildings": encode_tiles(city.industry_buildings), "import_orders": imports, "manufacturing_orders": manufacturing, "active_technology": city.active_technology, "research_progress": city.research_progress, "research_status": city.research_status, "selected_import_resource": city.selected_import_resource}

func serialize_combat(combat) -> Dictionary:
	var units: Array = []
	for unit_id in combat.sorted_unit_ids():
		var unit: Dictionary = combat.units[unit_id]
		var record := {"id": int(unit["id"]), "owner": int(unit["owner"]), "type": int(unit["type"]), "tile": encode_vector(unit["tile"]), "world_position": encode_vector(unit["world_position"]), "health": float(unit["health"]), "max_health": float(unit["max_health"]), "armor": float(unit["armor"]), "damage": float(unit["damage"]), "range": int(unit["range"]), "movement_speed": float(unit["movement_speed"]), "air": bool(unit["air"]), "command": int(unit["command"]), "target_id": int(unit["target_id"]), "path": encode_tiles(unit["path"]), "path_index": int(unit["path_index"]), "move_wait": int(unit["move_wait"]), "alive": bool(unit["alive"]), "defend_tile": encode_vector(unit["defend_tile"]), "weapon_cooldown": int(unit.get("weapon_cooldown", 0))}
		if unit.has("target_tile"):
			record["target_tile"] = encode_vector(unit["target_tile"])
		if unit.has("strategic_managed"):
			record["strategic_managed"] = bool(unit["strategic_managed"])
		units.append(record)
	return {"territory": encode_packed(combat.territory), "units": units, "next_unit_id": combat.next_unit_id, "ai_capital_owner": combat.ai_capital_owner, "player_capital_owner": combat.player_capital_owner, "capital_progress": encode_dictionary_entries(combat.capital_progress), "terrain_capture_progress": encode_dictionary_entries(combat.terrain_capture_progress)}

func serialize_strategic(strategic) -> Dictionary:
	var silos: Array = []
	var silo_tiles: Array = strategic.silos.keys()
	silo_tiles.sort()
	for tile in silo_tiles:
		var state: Dictionary = strategic.silos[tile]
		silos.append({"tile": encode_vector(tile), "stored": int(state["stored"]), "cooldown": int(state["cooldown"]), "production": int(state["production"])})
	var sams: Array = []
	var sam_tiles: Array = strategic.sam_cooldowns.keys()
	sam_tiles.sort()
	for tile in sam_tiles:
		sams.append({"tile": encode_vector(tile), "value": int(strategic.sam_cooldowns[tile])})
	var missiles: Array = []
	var missile_ids: Array = strategic.missiles.keys()
	missile_ids.sort()
	for missile_id in missile_ids:
		var missile: Dictionary = strategic.missiles[missile_id]
		missiles.append({"id": int(missile["id"]), "owner": int(missile["owner"]), "source": encode_vector(missile["source"]), "target": encode_vector(missile["target"]), "progress": float(missile["progress"]), "elapsed": int(missile["elapsed"]), "duration": int(missile["duration"]), "alive": bool(missile["alive"]), "intercepted": bool(missile["intercepted"])})
	return {"tick_count": strategic.tick_count, "silos": silos, "sam_cooldowns": sams, "missiles": missiles, "next_missile_id": strategic.next_missile_id}

func serialize_campaign(campaign) -> Dictionary:
	return {"phase": campaign.phase, "elapsed_ticks": campaign.elapsed_ticks, "victory_event_count": campaign.victory_event_count, "defeat_event_count": campaign.defeat_event_count, "defeated_nation": campaign.defeated_nation, "defeated_capital": encode_vector(campaign.defeated_capital), "victory_stats": campaign.victory_stats.duplicate(true)}

func serialize_ai(ai_campaign) -> Dictionary:
	return {"economy": serialize_city(ai_campaign.economy), "phase": ai_campaign.phase, "simulation_ticks": ai_campaign.simulation_ticks, "decision_count": ai_campaign.decision_count, "road_cursor": ai_campaign.road_cursor, "site_cursor": ai_campaign.site_cursor, "road_plan": encode_tiles(ai_campaign.road_plan), "building_sites": encode_tiles(ai_campaign.building_sites), "current_target": encode_vector(ai_campaign.current_target), "last_decision": ai_campaign.last_decision}

func deserialize_city(section: Dictionary, map_data):
	var tile_count: int = map_data.size.x * map_data.size.y
	for key in ["roads", "zones", "buildings", "rubble"]:
		if not valid_array(section.get(key), tile_count):
			return null
	if not valid_array(section.get("resources"), 7) or not valid_array(section.get("completed_technologies"), CityConfigScript.TECH_COUNT) or not valid_array(section.get("produced_units"), CityConfigScript.UNIT_COUNT):
		return null
	var city = CitySimulationScript.new(map_data)
	city.roads = decode_bytes(section["roads"])
	city.zones = decode_bytes(section["zones"])
	city.buildings = decode_bytes(section["buildings"])
	city.rubble = decode_bytes(section["rubble"])
	city.resources = decode_floats(section["resources"])
	city.completed_technologies = decode_bytes(section["completed_technologies"])
	city.produced_units = decode_ints(section["produced_units"])
	city.household_capacity = int(section.get("household_capacity", 0))
	city.occupied_households = int(section.get("occupied_households", 0))
	city.job_capacity = int(section.get("job_capacity", 0))
	city.employed_workforce = int(section.get("employed_workforce", 0))
	city.tick_count = int(section.get("tick_count", 0))
	city.active_technology = int(section.get("active_technology", 0))
	city.research_progress = float(section.get("research_progress", 0.0))
	city.research_status = String(section.get("research_status", "No active research"))
	city.selected_import_resource = int(section.get("selected_import_resource", CitySimulationScript.LedgerResource.FOOD))
	city.operation_workforce_remaining = int(section.get("operation_workforce_remaining", 0))
	city.operation_power_remaining = float(section.get("operation_power_remaining", 0.0))
	city.industry_buildings = decode_tile_list(section.get("industry_buildings", []), map_data)
	city.import_orders = decode_import_orders(section.get("import_orders", []))
	city.manufacturing_orders = decode_manufacturing_orders(section.get("manufacturing_orders", []), map_data)
	if city.industry_buildings.size() != Array(section.get("industry_buildings", [])).size() or city.import_orders.size() != Array(section.get("import_orders", [])).size() or city.manufacturing_orders.size() != Array(section.get("manufacturing_orders", [])).size():
		return null
	city.rebuild_coverage()
	return city

func encode_vector(value: Vector2i) -> Array:
	return [value.x, value.y]

func decode_vector(value: Variant) -> Vector2i:
	if typeof(value) != TYPE_ARRAY or Array(value).size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(value[0]), int(value[1]))

func encode_tiles(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(encode_vector(Vector2i(value)))
	return result

func encode_packed(values: Variant) -> Array:
	var result: Array = []
	for value in values:
		result.append(value)
	return result

func encode_dictionary_entries(values: Dictionary) -> Array:
	var result: Array = []
	var keys := values.keys()
	keys.sort()
	for key in keys:
		result.append({"key": key, "value": int(values[key])})
	return result

func valid_array(value: Variant, expected_size: int) -> bool:
	return typeof(value) == TYPE_ARRAY and Array(value).size() == expected_size

func decode_bytes(values: Array) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(values.size())
	for index in values.size():
		result[index] = int(values[index])
	return result

func decode_ints(values: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(values.size())
	for index in values.size():
		result[index] = int(values[index])
	return result

func decode_floats(values: Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(values.size())
	for index in values.size():
		result[index] = float(values[index])
	return result

func decode_tile_list(values: Variant, map_data) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		var tile := decode_vector(value)
		if not map_data.is_valid(tile):
			return []
		result.append(tile)
	return result

func decode_import_orders(values: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return []
		result.append({"resource": int(value.get("resource", -1)), "quantity": float(value.get("quantity", 0.0)), "cost": float(value.get("cost", 0.0)), "remaining": int(value.get("remaining", 0))})
	return result

func decode_manufacturing_orders(values: Variant, map_data) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return []
		var tile := decode_vector(value.get("tile", []))
		if not map_data.is_valid(tile):
			return []
		result.append({"tile": tile, "unit": int(value.get("unit", 0)), "remaining": int(value.get("remaining", 0))})
	return result

func decode_units(values: Variant, map_data) -> Dictionary:
	var result: Dictionary = {}
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var id := int(value.get("id", -1))
		var tile := decode_vector(value.get("tile", []))
		var world_position := decode_vector(value.get("world_position", []))
		var defend_tile := decode_vector(value.get("defend_tile", []))
		var path := decode_tile_list(value.get("path", []), map_data)
		if id < 1 or result.has(id) or not map_data.is_valid(tile) or not map_data.is_valid(world_position) or not map_data.is_valid(defend_tile) or path.size() != Array(value.get("path", [])).size():
			return {}
		var unit := {"id": id, "owner": int(value.get("owner", 0)), "type": int(value.get("type", 0)), "tile": tile, "world_position": world_position, "health": float(value.get("health", 0.0)), "max_health": float(value.get("max_health", 0.0)), "armor": float(value.get("armor", 0.0)), "damage": float(value.get("damage", 0.0)), "range": int(value.get("range", 0)), "movement_speed": float(value.get("movement_speed", 0.0)), "air": bool(value.get("air", false)), "command": int(value.get("command", 0)), "target_id": int(value.get("target_id", -1)), "path": path, "path_index": int(value.get("path_index", 0)), "move_wait": int(value.get("move_wait", 0)), "alive": bool(value.get("alive", false)), "defend_tile": defend_tile, "weapon_cooldown": int(value.get("weapon_cooldown", 0))}
		if value.has("target_tile"):
			var target_tile := decode_vector(value["target_tile"])
			if not map_data.is_valid(target_tile):
				return {}
			unit["target_tile"] = target_tile
		if value.has("strategic_managed"):
			unit["strategic_managed"] = bool(value["strategic_managed"])
		result[id] = unit
	return result

func decode_missiles(values: Variant, map_data) -> Dictionary:
	var result: Dictionary = {}
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var id := int(value.get("id", -1))
		var source := decode_vector(value.get("source", []))
		var target := decode_vector(value.get("target", []))
		if id < 1 or result.has(id) or not map_data.is_valid(source) or not map_data.is_valid(target):
			return {}
		result[id] = {"id": id, "owner": int(value.get("owner", 0)), "source": source, "target": target, "progress": float(value.get("progress", 0.0)), "elapsed": int(value.get("elapsed", 0)), "duration": int(value.get("duration", 1)), "alive": bool(value.get("alive", false)), "intercepted": bool(value.get("intercepted", false))}
	return result

func decode_tile_state_entries(values: Variant, map_data, fields: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var tile := decode_vector(value.get("tile", []))
		if not map_data.is_valid(tile):
			return {}
		var state: Dictionary = {}
		for field in fields:
			state[field] = int(value.get(field, 0))
		result[tile] = state
	return result

func decode_tile_values(values: Variant, map_data) -> Dictionary:
	var result: Dictionary = {}
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var tile := decode_vector(value.get("tile", []))
		if not map_data.is_valid(tile):
			return {}
		result[tile] = int(value.get("value", 0))
	return result

func decode_string_int_entries(values: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		result[String(value.get("key", ""))] = int(value.get("value", 0))
	return result

func decode_int_int_entries(values: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		result[int(value.get("key", -1))] = int(value.get("value", 0))
	return result

func fail_load(message: String) -> Dictionary:
	last_error = message
	return {}

func fail_save(started: int, message: String) -> bool:
	last_error = message
	last_save_duration_msec = float(Time.get_ticks_usec() - started) / 1000.0
	return false

func remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
