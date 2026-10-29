extends Node2D

const CAMERA_SPEED := 900.0
const MIN_ZOOM := 0.35
const MAX_ZOOM := 2.25
const ZOOM_STEP := 1.12
const DEBUG_UPDATE_INTERVAL := 0.25
const MapDataScript = preload("res://scripts/map_data.gd")
const WorldRendererScript = preload("res://scripts/world_renderer.gd")
const TileMarkerScript = preload("res://scripts/tile_marker.gd")
const DebugOverlayScript = preload("res://scripts/debug_overlay.gd")
const IsoMathScript = preload("res://scripts/iso_math.gd")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CityConfigScript = preload("res://scripts/city_config.gd")
const CombatSimulationScript = preload("res://scripts/combat_simulation.gd")
const CombatRendererScript = preload("res://scripts/combat_renderer.gd")
const StrategicSimulationScript = preload("res://scripts/strategic_simulation.gd")
const PrototypeHudScript = preload("res://scripts/prototype_hud.gd")
const CampaignStateScript = preload("res://scripts/campaign_state.gd")
const PersistenceManagerScript = preload("res://scripts/persistence_manager.gd")
const AICampaignControllerScript = preload("res://scripts/ai_campaign_controller.gd")

var map_data
var world_renderer
var city
var combat
var combat_renderer
var strategic
var ai_campaign
var campaign
var persistence
var hud
var missile_targeting := false
var interaction_mode := ""
var interaction_label := ""
var camera: Camera2D
var hover_marker
var selection_marker
var overlay
var target_zoom := 0.75
var hovered_tile := Vector2i(-1, -1)
var placement_preview
var selected_tile := Vector2i(-1, -1)
var dragging := false
var last_mouse_world := Vector2(INF, INF)
var debug_update_elapsed := DEBUG_UPDATE_INTERVAL
var simulation_elapsed := 0.0
var autosave_elapsed := 0.0
var action_feedback := ""
var action_feedback_remaining := 0.0

func _ready() -> void:
	map_data = MapDataScript.new(MapDataScript.MAP_SIZE, development_seed())
	city = CitySimulationScript.new(map_data)
	combat = CombatSimulationScript.new(map_data, city)
	strategic = StrategicSimulationScript.new(map_data, city, combat)
	ai_campaign = AICampaignControllerScript.new(map_data, city, combat, strategic)
	campaign = CampaignStateScript.new()
	persistence = PersistenceManagerScript.new()
	persistence.configure_autosave_rotation()
	world_renderer = WorldRendererScript.new()
	add_child(world_renderer)
	world_renderer.configure(map_data, city, ai_campaign.economy)
	combat_renderer = CombatRendererScript.new()
	add_child(combat_renderer)
	combat_renderer.configure(map_data, combat, strategic)
	camera = Camera2D.new()
	camera.position = IsoMathScript.tile_to_world(map_data.size / 2)
	camera.zoom = Vector2(target_zoom, target_zoom)
	add_child(camera)
	hover_marker = TileMarkerScript.new()
	add_child(hover_marker)
	selection_marker = TileMarkerScript.new()
	add_child(selection_marker)
	placement_preview = preload("res://scripts/placement_preview.gd").new()
	add_child(placement_preview)
	overlay = DebugOverlayScript.new()
	overlay.visible = false
	add_child(overlay)
	hud = PrototypeHudScript.new()
	add_child(hud)
	hud.configure(self)
	world_renderer.update_visibility(camera)

func development_seed() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--world-seed="):
			var seed_text := argument.trim_prefix("--world-seed=")
			if seed_text.is_valid_int():
				return seed_text.to_int()
	return MapDataScript.SEED

func regenerate_world(new_seed: int) -> void:
	map_data = MapDataScript.new(MapDataScript.MAP_SIZE, new_seed)
	city = CitySimulationScript.new(map_data)
	combat = CombatSimulationScript.new(map_data, city)
	strategic = StrategicSimulationScript.new(map_data, city, combat)
	ai_campaign = AICampaignControllerScript.new(map_data, city, combat, strategic)
	campaign = CampaignStateScript.new()
	world_renderer.configure(map_data, city, ai_campaign.economy)
	combat_renderer.configure(map_data, combat, strategic)
	selected_tile = Vector2i(-1, -1)
	selection_marker.clear()
	last_mouse_world = Vector2(INF, INF)
	action_feedback = ""
	action_feedback_remaining = 0.0
	interaction_mode = ""
	missile_targeting = false
	if placement_preview != null: placement_preview.clear()
	simulation_elapsed = 0.0
	autosave_elapsed = 0.0
	world_renderer.update_visibility(camera)
	if hud != null: hud.refresh()

func _process(delta: float) -> void:
	var controls_enabled: bool = campaign == null or not campaign.is_outcome_pending()
	var direction := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	).normalized() if controls_enabled else Vector2.ZERO
	if direction != Vector2.ZERO:
		camera.position += direction * CAMERA_SPEED * delta / target_zoom
	target_zoom = clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
	var smoothed := lerpf(camera.zoom.x, target_zoom, minf(delta * 12.0, 1.0))
	camera.zoom = Vector2(smoothed, smoothed)
	update_hover()
	world_renderer.update_visibility(camera)
	if campaign.simulation_enabled():
		simulation_elapsed += delta
		while simulation_elapsed >= CityConfigScript.TICK_SECONDS and campaign.simulation_enabled():
			simulation_elapsed -= CityConfigScript.TICK_SECONDS
			run_simulation_tick()
	else:
		simulation_elapsed = 0.0
	if campaign.simulation_enabled():
		autosave_elapsed += delta
		if autosave_elapsed >= PersistenceManagerScript.AUTOSAVE_INTERVAL_SECONDS:
			autosave_elapsed = 0.0
			perform_autosave()
	if action_feedback_remaining > 0.0:
		action_feedback_remaining = maxf(0.0, action_feedback_remaining - delta)
	debug_update_elapsed += delta
	if debug_update_elapsed >= DEBUG_UPDATE_INTERVAL:
		debug_update_elapsed = 0.0
		update_debug_overlay(delta)

func run_simulation_tick() -> bool:
	if campaign == null or not campaign.simulation_enabled():
		return false
	campaign.record_simulation_tick()
	var changed_tiles: Array[Vector2i] = city.tick()
	changed_tiles.append_array(ai_campaign.tick())
	var territory_changed: Array[Vector2i] = combat.tick()
	changed_tiles.append_array(combat.damaged_structure_tiles)
	if not territory_changed.is_empty():
		combat_renderer.refresh_territory(territory_changed)
	changed_tiles.append_array(strategic.tick())
	world_renderer.refresh_tiles(changed_tiles)
	combat_renderer.refresh_units()
	if campaign.observe_capital_ownership(combat, city, map_data):
		on_campaign_outcome()
	return true

func on_campaign_outcome() -> void:
	if placement_preview != null: placement_preview.clear()
	interaction_mode = ""
	interaction_label = ""
	missile_targeting = false
	dragging = false
	combat_renderer.set_missile_preview(false)
	action_feedback = ""
	action_feedback_remaining = 0.0
	simulation_elapsed = 0.0
	if hud != null:
		hud.refresh()

func hud_continue_sandbox() -> void:
	if campaign.continue_in_sandbox():
		if perform_autosave(false):
			set_persistence_feedback("Sandbox mode: world preserved · Autosaved", true)
		else:
			set_persistence_feedback("Sandbox resumed; autosave failed: %s" % persistence.last_error, false)

func hud_restart_prototype() -> void:
	regenerate_world(development_seed())
	set_persistence_feedback("Prototype restarted", true)

func hud_save_game() -> void:
	if campaign.is_outcome_pending():
		set_persistence_feedback("Cannot save while victory summary is open" if campaign.is_victory_pending() else "Cannot save while defeat summary is open", false)
		return
	var succeeded: bool = persistence.save_game(persistence.manual_save_path, map_data, city, combat, strategic, campaign, "manual", -1, ai_campaign)
	set_persistence_feedback("Game saved" if succeeded else "Save failed: %s" % persistence.last_error, succeeded)

func hud_load_game() -> void:
	load_game_from_path(persistence.manual_save_path)

func hud_load_latest_autosave() -> void:
	var path: String = persistence.latest_autosave_path()
	if path.is_empty():
		set_persistence_feedback("Load failed: %s" % persistence.last_error, false)
		return
	load_game_from_path(path)

func load_game_from_path(path: String) -> void:
	var loaded: Dictionary = persistence.load_game(path)
	if loaded.is_empty():
		set_persistence_feedback("Load failed: %s" % persistence.last_error, false)
		return
	apply_loaded_state(loaded)
	set_persistence_feedback("Game loaded from previous-save backup" if persistence.last_load_used_backup else "Game loaded", true)

func perform_autosave(show_feedback: bool = true) -> bool:
	var succeeded: bool = persistence.save_autosave(map_data, city, combat, strategic, campaign, "", ai_campaign)
	if show_feedback:
		set_persistence_feedback("Autosaved" if succeeded else "Autosave failed: %s" % persistence.last_error, succeeded)
	return succeeded

func set_persistence_feedback(message: String, succeeded: bool) -> void:
	action_feedback = message
	action_feedback_remaining = 1.5 if succeeded else 3.0
	debug_update_elapsed = DEBUG_UPDATE_INTERVAL
	if hud != null:
		hud.refresh()

func apply_loaded_state(loaded: Dictionary) -> void:
	map_data = loaded["map"]
	city = loaded["city"]
	combat = loaded["combat"]
	strategic = loaded["strategic"]
	campaign = loaded["campaign"]
	ai_campaign = loaded["ai_campaign"] if loaded.has("ai_campaign") else AICampaignControllerScript.new(map_data, city, combat, strategic)
	ai_campaign.configure(city, combat, strategic)
	world_renderer.configure(map_data, city, ai_campaign.economy)
	combat_renderer.configure(map_data, combat, strategic)
	var owned_tiles: Array[Vector2i] = []
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			if combat.territory[map_data.index(tile)] != 0:
				owned_tiles.append(tile)
	if not owned_tiles.is_empty():
		combat_renderer.refresh_territory(owned_tiles)
	selected_tile = Vector2i(-1, -1)
	hovered_tile = Vector2i(-1, -1)
	combat.clear_selection()
	strategic.selected_silo = Vector2i(-1, -1)
	selection_marker.clear()
	hover_marker.clear()
	if placement_preview != null: placement_preview.clear()
	interaction_mode = ""
	interaction_label = ""
	missile_targeting = false
	dragging = false
	last_mouse_world = Vector2(INF, INF)
	simulation_elapsed = 0.0
	autosave_elapsed = 0.0
	camera.position = IsoMathScript.tile_to_world(map_data.size / 2)
	combat_renderer.set_missile_preview(false)
	world_renderer.update_visibility(camera)
	if hud != null:
		hud.current_context_key = ""
		hud.refresh()

func update_hover() -> void:
	var mouse_world := get_global_mouse_position()
	if mouse_world.is_equal_approx(last_mouse_world):
		update_placement_preview()
		return
	set_hover_world(mouse_world)

func set_hover_world(mouse_world: Vector2) -> void:
	last_mouse_world = mouse_world
	hovered_tile = IsoMathScript.world_to_tile(mouse_world, map_data.size)
	if hovered_tile.x >= 0:
		hover_marker.set_tile(hovered_tile, Color("f4dc75"))
		if missile_targeting: combat_renderer.set_missile_preview(true, hovered_tile)
	else:
		hover_marker.clear()
		if missile_targeting: combat_renderer.set_missile_preview(false)
	update_placement_preview()

func placement_building_type() -> int:
	if not interaction_mode.begins_with("Place "): return 0
	return {"power": 1, "water": 2, "fire": 3, "farm": 6, "materials": 7, "refinery": 8, "import": 9, "defense": 10, "university": 11, "lab": 12, "barracks": 13, "vehicle": 14, "drone": 15, "airbase": 16, "sam": 17, "silo": 18}.get(interaction_label, 0)

func update_placement_preview() -> void:
	if placement_preview == null: return
	placement_preview.update_preview(city, hovered_tile, placement_building_type())
	if hud != null and placement_building_type() != 0:
		hud.status_label.text = placement_preview.reason if not placement_preview.reason.is_empty() else "Click to build at %s" % hovered_tile

func change_zoom(multiplier: float) -> void:
	target_zoom = clampf(target_zoom * multiplier, MIN_ZOOM, MAX_ZOOM)

func update_debug_overlay(frame_delta: float) -> void:
	var status: String = city.shortage_reason(selected_tile)
	if action_feedback_remaining > 0.0 and not action_feedback.is_empty():
		status = action_feedback
	var city_summary: String = city.debug_summary()
	if ai_campaign != null:
		city_summary += "\n" + ai_campaign.summary()
	var selection_summary: String = city.selection_summary(selected_tile)
	if not selection_summary.is_empty():
		city_summary += "\n" + selection_summary
	var combat_summary: String = combat.selected_summary()
	if not combat_summary.is_empty():
		city_summary += "\n" + combat_summary
	if not combat.status_message.is_empty():
		city_summary += "\n" + combat.status_message
	var strategic_summary: String = strategic.silo_summary(selected_tile)
	if strategic_summary.is_empty(): strategic_summary = strategic.sam_summary(selected_tile)
	if not strategic_summary.is_empty(): city_summary += "\n" + strategic_summary
	if missile_targeting and map_data.is_valid(hovered_tile) and city.get_building(selected_tile) == CitySimulationScript.Building.MISSILE_SILO:
		city_summary += "\nMissile ETA: %.0fs" % strategic.missile_eta_seconds(selected_tile, hovered_tile)
	overlay.update_stats(Engine.get_frames_per_second(), frame_delta * 1000.0, world_renderer.visible_chunks, world_renderer.rendered_tiles, camera.zoom.x, hovered_tile, selected_tile, status, city_summary)
	hud.refresh()

func selection_description() -> String:
	var lines: Array[String] = []
	var city_text: String = city.selection_summary(selected_tile)
	if not city_text.is_empty(): lines.append(city_text)
	var combat_text: String = combat.selected_summary()
	if not combat_text.is_empty(): lines.append(combat_text)
	var silo_text: String = strategic.silo_summary(selected_tile)
	if not silo_text.is_empty(): lines.append(silo_text)
	var sam_text: String = strategic.sam_summary(selected_tile)
	if not sam_text.is_empty(): lines.append(sam_text)
	return "\n".join(lines) if not lines.is_empty() else "Click a tile, building, or unit"

func begin_placement(tool: String, label: String) -> void:
	cancel_interaction()
	interaction_mode = "Place %s" % label
	interaction_label = tool
	action_feedback = "Select tile for %s" % label
	action_feedback_remaining = 2.0
	hud.refresh()
	update_placement_preview()

func cancel_interaction() -> void:
	interaction_mode = ""
	interaction_label = ""
	missile_targeting = false
	combat_renderer.set_missile_preview(false)
	if placement_preview != null: placement_preview.clear()
	if hud != null: hud.refresh()

func apply_placement(tile: Vector2i) -> void:
	var changed := false
	match interaction_label:
		"road": changed = city.place_road(tile)
		"residential": changed = city.place_zone(tile, CitySimulationScript.Zone.RESIDENTIAL)
		"commercial": changed = city.place_zone(tile, CitySimulationScript.Zone.COMMERCIAL)
		"bulldoze": changed = city.bulldoze(tile)
		"power": changed = city.place_utility(tile, CitySimulationScript.Building.POWER_PLANT)
		"water": changed = city.place_utility(tile, CitySimulationScript.Building.WATER_FACILITY)
		"fire": changed = city.place_utility(tile, CitySimulationScript.Building.FIRE_STATION)
		"farm": changed = city.place_industry_building(tile, CitySimulationScript.Building.FARM)
		"materials": changed = city.place_industry_building(tile, CitySimulationScript.Building.MATERIALS_PLANT)
		"refinery": changed = city.place_industry_building(tile, CitySimulationScript.Building.REFINERY)
		"import": changed = city.place_industry_building(tile, CitySimulationScript.Building.IMPORT_DEPOT)
		"defense": changed = city.place_industry_building(tile, CitySimulationScript.Building.DEFENSE_FACTORY)
		"university": changed = city.place_industry_building(tile, CitySimulationScript.Building.UNIVERSITY)
		"lab": changed = city.place_industry_building(tile, CitySimulationScript.Building.RESEARCH_LAB)
		"barracks": changed = city.place_industry_building(tile, CitySimulationScript.Building.BARRACKS)
		"vehicle": changed = city.place_industry_building(tile, CitySimulationScript.Building.VEHICLE_FACTORY)
		"drone": changed = city.place_industry_building(tile, CitySimulationScript.Building.DRONE_FACTORY)
		"airbase": changed = city.place_industry_building(tile, CitySimulationScript.Building.AIRBASE)
		"sam": changed = city.place_industry_building(tile, CitySimulationScript.Building.SAM_SITE)
		"silo": changed = city.place_industry_building(tile, CitySimulationScript.Building.MISSILE_SILO)
	if changed:
		world_renderer.refresh_tile(tile)
		selected_tile = tile
		selection_marker.set_tile(tile, Color("ff926b"))
	finish_city_feedback(changed)
	if changed: cancel_interaction()
	else: update_placement_preview()

func hud_queue_unit(unit_type: int) -> void:
	finish_city_feedback(city.queue_unit(selected_tile, unit_type))

func hud_deploy_unit(unit_type: int) -> void:
	finish_combat_feedback(combat.deploy_produced_unit(unit_type, selected_tile))
	combat_renderer.refresh_units()

func hud_command(command: String) -> void:
	var succeeded := false
	match command:
		"move", "attack": interaction_mode = "Select %s destination" % command.capitalize()
		"defend": succeeded = combat.issue_defend(combat.selected_unit_id)
		"stop": succeeded = combat.issue_stop(combat.selected_unit_id)
	if command == "move" or command == "attack":
		interaction_label = command
		action_feedback = interaction_mode
		action_feedback_remaining = 2.0
	else: finish_combat_feedback(succeeded)
	hud.refresh()

func hud_start_research() -> void: finish_city_feedback(city.start_next_research())
func hud_order_import() -> void: finish_city_feedback(city.place_import_order(city.selected_import_resource))
func hud_cycle_import() -> void:
	city.cycle_import_resource()
	finish_city_feedback(true)
func hud_manufacture_missile() -> void: finish_strategic_feedback(strategic.queue_missile(selected_tile))
func hud_target_missile() -> void:
	if city.get_building(selected_tile) == CitySimulationScript.Building.MISSILE_SILO:
		strategic.selected_silo = selected_tile; missile_targeting = true; interaction_mode = "Missile Targeting"; combat_renderer.set_missile_preview(true, hovered_tile); finish_strategic_feedback(true)
	else: finish_strategic_feedback(strategic.reject("Select Missile Silo"))

func finish_city_action(changed: bool) -> void:
	if changed:
		world_renderer.refresh_tile(selected_tile)
	finish_city_feedback(changed)

func finish_city_feedback(succeeded: bool) -> void:
	if succeeded:
		action_feedback = ""
		action_feedback_remaining = 0.0
	else:
		action_feedback = city.last_action_reason
		action_feedback_remaining = 2.5
	debug_update_elapsed = DEBUG_UPDATE_INTERVAL
	if hud != null: hud.refresh()

func finish_combat_feedback(succeeded: bool) -> void:
	if succeeded:
		action_feedback = combat.last_action_reason
		action_feedback_remaining = 1.5
	else:
		action_feedback = combat.last_action_reason
		action_feedback_remaining = 2.5
	debug_update_elapsed = DEBUG_UPDATE_INTERVAL
	if hud != null: hud.refresh()

func finish_strategic_feedback(succeeded: bool) -> void:
	action_feedback = strategic.last_action_reason
	action_feedback_remaining = 1.5 if succeeded else 2.5
	debug_update_elapsed = DEBUG_UPDATE_INTERVAL
	if hud != null: hud.refresh()

func _unhandled_input(event: InputEvent) -> void:
	if campaign != null and campaign.is_outcome_pending():
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		set_hover_world(get_global_transform_with_canvas().affine_inverse() * event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not interaction_mode.is_empty():
		cancel_interaction()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			change_zoom(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			change_zoom(1.0 / ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and hovered_tile.x >= 0:
			if missile_targeting:
				finish_strategic_feedback(strategic.launch_missile(selected_tile, hovered_tile))
				missile_targeting = false
				interaction_mode = ""
				combat_renderer.set_missile_preview(false)
				return
			if interaction_mode.begins_with("Place "):
				apply_placement(hovered_tile)
				return
			if interaction_label == "move" or interaction_label == "attack":
				var command_target: int = combat.unit_at(hovered_tile)
				var command_ok: bool = combat.issue_move(combat.selected_unit_id, hovered_tile) if interaction_label == "move" else (command_target >= 0 and combat.issue_attack(combat.selected_unit_id, command_target))
				finish_combat_feedback(command_ok)
				cancel_interaction()
				combat_renderer.refresh_units()
				return
			selected_tile = hovered_tile
			strategic.selected_silo = selected_tile if city.get_building(selected_tile) == CitySimulationScript.Building.MISSILE_SILO else Vector2i(-1, -1)
			selection_marker.set_tile(selected_tile, Color("ff926b"))
			combat.select_unit_at(selected_tile)
			combat_renderer.refresh_units()
			action_feedback = ""
			action_feedback_remaining = 0.0
			if hud != null: hud.refresh()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and hovered_tile.x >= 0:
			if combat.selected_unit_id < 0:
				finish_combat_feedback(combat.reject("No unit selected"))
			else:
				var target_id: int = combat.unit_at(hovered_tile)
				if target_id >= 0:
					finish_combat_feedback(combat.issue_attack(combat.selected_unit_id, target_id))
				else:
					finish_combat_feedback(combat.issue_move(combat.selected_unit_id, hovered_tile))
				combat_renderer.refresh_units()
	if event is InputEventMouseMotion and dragging:
		camera.position -= event.relative / camera.zoom
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			overlay.visible = not overlay.visible
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS or event.keycode == KEY_KP_ADD or event.physical_keycode == KEY_EQUAL:
			change_zoom(ZOOM_STEP)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT or event.physical_keycode == KEY_MINUS:
			change_zoom(1.0 / ZOOM_STEP)
		elif event.keycode == KEY_ESCAPE:
			combat.clear_selection()
			cancel_interaction()
			combat_renderer.refresh_units()
		elif event.keycode == KEY_SPACE:
			finish_combat_feedback(combat.issue_stop(combat.selected_unit_id))
			combat_renderer.refresh_units()
		elif event.keycode == KEY_G and combat.selected_unit_id >= 0:
			finish_combat_feedback(combat.issue_defend(combat.selected_unit_id))
			combat_renderer.refresh_units()
		elif event.keycode >= KEY_F1 and event.keycode <= KEY_F7:
			finish_combat_feedback(combat.deploy_produced_unit(event.keycode - KEY_F1 + 1, selected_tile))
			combat_renderer.refresh_units()
		elif event.keycode == KEY_F8:
			finish_combat_feedback(combat.spawn_developer_ai_force())
			combat_renderer.refresh_units()
		elif event.keycode == KEY_7:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.SAM_SITE))
		elif event.keycode == KEY_8:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.MISSILE_SILO))
		elif event.keycode == KEY_F9:
			finish_strategic_feedback(strategic.queue_missile(selected_tile))
		elif event.keycode == KEY_F10:
			if city.get_building(selected_tile) == CitySimulationScript.Building.MISSILE_SILO:
				strategic.selected_silo = selected_tile
				missile_targeting = true
				interaction_mode = "Missile Targeting"
				combat_renderer.set_missile_preview(true, hovered_tile)
				finish_strategic_feedback(strategic.accept("Select any in-bounds missile target"))
			else:
				finish_strategic_feedback(strategic.reject("Select Missile Silo"))
		elif event.keycode == KEY_P and map_data.place_marker(selected_tile):
			world_renderer.refresh_tile(selected_tile)
		elif (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and map_data.remove_marker(selected_tile):
			world_renderer.refresh_tile(selected_tile)
		elif event.keycode == KEY_R:
			finish_city_action(city.place_road(selected_tile))
		elif event.keycode == KEY_1:
			finish_city_action(city.place_zone(selected_tile, CitySimulationScript.Zone.RESIDENTIAL))
		elif event.keycode == KEY_2:
			finish_city_action(city.place_zone(selected_tile, CitySimulationScript.Zone.COMMERCIAL))
		elif event.keycode == KEY_3:
			finish_city_action(city.place_utility(selected_tile, CitySimulationScript.Building.POWER_PLANT))
		elif event.keycode == KEY_4:
			finish_city_action(city.place_utility(selected_tile, CitySimulationScript.Building.WATER_FACILITY))
		elif event.keycode == KEY_5:
			finish_city_action(city.place_utility(selected_tile, CitySimulationScript.Building.FIRE_STATION))
		elif event.keycode == KEY_B:
			finish_city_action(city.bulldoze(selected_tile))
		elif event.keycode == KEY_F:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.FARM))
		elif event.keycode == KEY_M:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.MATERIALS_PLANT))
		elif event.keycode == KEY_Y:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.REFINERY))
		elif event.keycode == KEY_I:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.IMPORT_DEPOT))
		elif event.keycode == KEY_G:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.DEFENSE_FACTORY))
		elif event.keycode == KEY_U:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.UNIVERSITY))
		elif event.keycode == KEY_L:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.RESEARCH_LAB))
		elif event.keycode == KEY_N:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.BARRACKS))
		elif event.keycode == KEY_V:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.VEHICLE_FACTORY))
		elif event.keycode == KEY_O:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.DRONE_FACTORY))
		elif event.keycode == KEY_H:
			finish_city_action(city.place_industry_building(selected_tile, CitySimulationScript.Building.AIRBASE))
		elif event.keycode == KEY_T:
			finish_city_feedback(city.start_next_research())
		elif event.keycode == KEY_COMMA:
			city.cycle_import_resource()
			finish_city_feedback(true)
		elif event.keycode == KEY_PERIOD:
			finish_city_feedback(city.place_import_order(city.selected_import_resource))
		elif event.keycode == KEY_Q:
			finish_city_feedback(city.queue_unit(selected_tile, CitySimulationScript.UnitType.INFANTRY))
		elif event.keycode == KEY_E:
			finish_city_feedback(city.queue_unit(selected_tile, CitySimulationScript.UnitType.TANK))
		elif event.keycode == KEY_C:
			finish_city_feedback(city.queue_unit(selected_tile, CitySimulationScript.UnitType.ARTILLERY))
		elif event.keycode == KEY_X:
			finish_city_feedback(city.queue_unit(selected_tile, CitySimulationScript.UnitType.ROBOT_UNIT))
		elif event.keycode == KEY_Z:
			finish_city_feedback(city.queue_unit(selected_tile, CitySimulationScript.UnitType.RECON_DRONE))
		elif event.keycode == KEY_J:
			finish_city_feedback(city.queue_unit(selected_tile, CitySimulationScript.UnitType.BOMBER))
		elif event.keycode == KEY_K:
			finish_city_feedback(city.queue_unit(selected_tile, CitySimulationScript.UnitType.FIGHTER))
