extends SceneTree

const Map = preload("res://scripts/map_data.gd")
const City = preload("res://scripts/city_simulation.gd")
const Combat = preload("res://scripts/combat_simulation.gd")
const Strategic = preload("res://scripts/strategic_simulation.gd")
const Campaign = preload("res://scripts/campaign_state.gd")
const AI = preload("res://scripts/ai_campaign_controller.gd")
const Persistence = preload("res://scripts/persistence_manager.gd")

var failures: Array[String] = []
var directory := "/tmp/strategy-save-safety-%d" % OS.get_process_id()
var checks := 0

func _init() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func fixture() -> Dictionary:
	var map = Map.new()
	var city = City.new(map)
	var combat = Combat.new(map, city)
	var strategic = Strategic.new(map, city, combat)
	var campaign = Campaign.new()
	var ai = AI.new(map, city, combat, strategic)
	var unit_id: int = combat.spawn_developer_unit(1, 1, map.player_capital)
	combat.issue_move(unit_id, map.ai_capital)
	return {"map": map, "city": city, "combat": combat, "strategic": strategic, "campaign": campaign, "ai": ai}

func mutate(document: Dictionary, path: Array, value: Variant) -> Dictionary:
	var changed: Dictionary = document.duplicate(true)
	var current: Variant = changed
	for index in path.size() - 1:
		current = current[path[index]]
	current[path[-1]] = value
	return changed

func run() -> void:
	var s := fixture()
	var manager = Persistence.new()
	var valid: Dictionary = JSON.parse_string(JSON.stringify(manager.create_save_data(s.map, s.city, s.combat, s.strategic, s.campaign, "manual", -1, s.ai)))
	if manager.reconstruct(valid).is_empty():
		push_error("Fixture rejected: " + manager.last_error)
		quit(1)
		return
	# The first cases are safe reproductions of data the old loader accepted.
	var cases := [
		[["city", "resources", 0], -1],
		[["city", "import_orders"], [{"resource": 99, "quantity": 10, "cost": 1, "remaining": 1}]],
		[["combat", "next_unit_id"], 1],
		[["combat", "units", 0, "type"], 99],
		[["ai", "phase"], 99],
	]
	if OS.get_cmdline_user_args().has("--baseline-probe"):
		for case in cases:
			expect(manager.reconstruct(mutate(valid, case[0], case[1])).is_empty(), "Must reject %s" % [case[0]])
		finish()
		return
	cases.append_array([
		[["version"], "1"], [["version"], 1.5], [["map"], []],
		[["map", "size"], [9223372036854775807, 2]],
		[["map", "size"], [128, -1]], [["map", "size"], [128.5, 128]],
		[["map", "seed"], {}], [["map", "terrain", 0], 256],
		[["map", "terrain", 0], "grass"], [["map", "deposits", 0], 4],
		[["map", "bridges", 0], 2], [["map", "player_capital"], ["a", 3]],
		[["city", "roads", 0], -1], [["city", "zones", 0], 3],
		[["city", "buildings", 0], 19], [["city", "resources", 0], INF],
		[["city", "resources", 0], NAN], [["city", "resources", 0], "500"],
		[["city", "resources"], {}], [["city", "produced_units", 1], 0.5],
		[["city", "active_technology"], 8], [["city", "selected_import_resource"], 0],
		[["city", "import_orders"], {}], [["city", "manufacturing_orders"], "orders"],
		[["city", "manufacturing_orders"], [{"tile": valid.map.player_capital, "unit": 1, "remaining": 1}]],
		[["city", "industry_buildings"], [[-1, -1]]],
		[["combat", "territory", 0], 3], [["combat", "units"], {}],
		[["combat", "units", 0, "owner"], 0], [["combat", "units", 0, "command"], 8],
		[["combat", "units", 0, "path"], {}], [["combat", "units", 0, "path_index"], 999999],
		[["combat", "units", 0, "health"], -1], [["combat", "units", 0, "alive"], "true"],
		[["combat", "units", 0, "target_id"], 999], [["combat", "units", 0, "tile"], [-1, 0]],
		[["combat", "units", 0, "world_position"], [1.5, 2]],
		[["combat", "capital_progress"], [{"key": "ai:999", "value": 1}]],
		[["combat", "terrain_capture_progress"], [{"key": 999, "value": 1}]],
		[["strategic", "missiles"], [{"id": 1, "owner": 1, "source": valid.map.player_capital, "target": valid.map.ai_capital, "elapsed": 0, "duration": 0, "progress": 0, "alive": true, "intercepted": false}]],
		[["strategic", "silos"], [{"tile": valid.map.player_capital, "stored": 4, "cooldown": 0, "production": 0}]],
		[["strategic", "sam_cooldowns"], [{"tile": valid.map.player_capital, "value": -1}]],
		[["ai"], []], [["ai", "economy", "resources", 3], -10],
		[["ai", "road_plan"], {}], [["ai", "road_cursor"], 99],
		[["campaign", "phase"], 4], [["campaign", "victory_stats"], []],
		[["metadata"], []], [["metadata", "autosave_sequence"], "latest"],
	])
	for case in cases:
		var result: Dictionary = manager.reconstruct(mutate(valid, case[0], case[1]))
		expect(result.is_empty() and not manager.last_error.is_empty(), "Must reject malformed %s" % [case[0]])
	var duplicated := valid.duplicate(true)
	duplicated.combat.units.append(duplicated.combat.units[0].duplicate(true))
	expect(manager.reconstruct(duplicated).is_empty(), "Duplicate unit IDs must reject")
	var original_money: float = s.city.resources[0]
	expect(manager.reconstruct(valid).size() > 0 and s.city.resources[0] == original_money, "Valid reconstruction must succeed without mutating the source simulation")
	var legacy := valid.duplicate(true)
	legacy.erase("ai")
	expect(not manager.reconstruct(legacy).is_empty(), "Earlier version-1 saves without AI remain supported")
	save_recovery(s, manager)
	finish()

func save_recovery(s: Dictionary, manager) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory + "/manual.json"
	expect(manager.save_game(path, s.map, s.city, s.combat, s.strategic, s.campaign, "manual", -1, s.ai), "Initial save must succeed")
	var previous := FileAccess.get_file_as_bytes(path)
	# Simulate interruption after the original was moved aside but before the
	# verified temporary file replaced it. Recovery must be read-only.
	DirAccess.rename_absolute(path, path + ".backup")
	expect(not manager.load_game(path).is_empty() and manager.last_load_used_backup, "Missing primary must recover the verified backup")
	expect(not FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path + ".backup") == previous, "Recovery must not overwrite either file")
	var corrupt := FileAccess.open(path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	expect(not manager.load_game(path).is_empty() and manager.last_load_used_backup, "Corrupt primary must recover the backup")
	# A directory at the temporary-file path forces a real write failure.
	DirAccess.make_dir_absolute(path + ".tmp")
	expect(not manager.save_game(path, s.map, s.city, s.combat, s.strategic, s.campaign), "Temporary-file write failure must be reported")
	expect(FileAccess.get_file_as_bytes(path + ".backup") == previous, "Failed save must preserve the last valid backup")
	DirAccess.remove_absolute(path + ".tmp")
	expect(manager.save_game(path, s.map, s.city, s.combat, s.strategic, s.campaign, "manual", -1, s.ai), "A new valid save must replace a corrupt primary without destroying recovery data early")
	expect(not manager.load_game(path).is_empty() and not manager.last_load_used_backup, "Successful replacement loads the primary")
	# A structurally invalid newest autosave must not hide an older valid slot.
	manager.autosave_directory = directory
	manager.save_autosave(s.map, s.city, s.combat, s.strategic, s.campaign, "", s.ai)
	var good_path: String = manager.latest_autosave_path()
	manager.save_autosave(s.map, s.city, s.combat, s.strategic, s.campaign, "", s.ai)
	var bad_path: String = manager.latest_autosave_path()
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bad_path))
	document.city.resources[0] = -1
	var file := FileAccess.open(bad_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	expect(manager.latest_autosave_path() == good_path, "Latest-autosave lookup must skip semantically invalid saves")
	var oversized_path := directory + "/oversized.json"
	var oversized := FileAccess.open(oversized_path, FileAccess.WRITE)
	oversized.store_string(" ".repeat(Persistence.MAX_SAVE_BYTES + 1))
	oversized.close()
	expect(manager.load_game(oversized_path).is_empty() and manager.last_error.contains("16 MiB"), "Oversized input must be rejected before JSON parsing")
	var invalid_root := FileAccess.open(directory + "/array.json", FileAccess.WRITE)
	invalid_root.store_string("[]")
	invalid_root.close()
	expect(manager.load_game(directory + "/array.json").is_empty() and manager.last_error.contains("root"), "A JSON array root must reject without a cast error")
	for filename in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)

func finish() -> void:
	if failures.is_empty():
		print("Save safety validation passed: %d rejection, recovery, and compatibility checks." % checks)
	else:
		for message in failures:
			push_error(message)
	quit(0 if failures.is_empty() else 1)
