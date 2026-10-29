extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const IsoMathScript = preload("res://scripts/iso_math.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func run() -> void:
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	# AI commands share the combat API, so old AI feedback must not become
	# the player's error when right-clicking without a selected unit.
	main.combat.last_action_reason = "Attack ordered"
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = main.get_global_transform_with_canvas() * IsoMathScript.tile_to_world(Vector2i(64, 64))
	main._unhandled_input(click)
	expect(main.action_feedback == "No unit selected", "Missing selection must not display an earlier AI command as success")
	expect(main.hud != null, "Prototype HUD must initialize")
	expect(main.hud.scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "HUD must not require horizontal scrolling")
	expect(main.hud.root_panel.size.x >= 250.0, "HUD panel must retain a usable width")
	expect(main.hud.resources_label.size.x >= 300.0, "Resource bar must retain a visible horizontal area")
	expect(main.hud.toolbar_panel.visible and main.hud.toolbar_panel.size.x > 400.0, "Active campaign must show the compact lower construction toolbar")
	expect(not main.hud.palette_panel.visible and not main.hud.command_panel.visible, "No contextual palette or command strip should obscure an unselected active map")
	main.hud.open_palette("Utilities")
	expect(main.hud.palette_panel.visible and find_button(main.hud.palette_panel, "ϟ Power Plant") != null, "Toolbar categories must open an icon-labelled construction palette")
	main.hud.open_palette("Military")
	await process_frame
	expect(main.hud.palette_panel.get_global_rect().encloses(find_button(main.hud.palette_panel, "▲ Missile Silo  🔒").get_global_rect()), "Last military tool must fit inside the palette")
	expect(find_button(main.hud.palette_panel, "▲ Missile Silo  🔒") != null, "Locked construction must remain visible with a clear lock state")
	main.hud.palette_panel.visible = false
	main.hud.toggle_forces()
	await process_frame
	expect(main.hud.force_panel.get_global_rect().encloses(main.hud.force_view_buttons[-1].get_global_rect()), "Fighter deployment must fit inside the Forces panel")
	expect(not main.hud.force_panel.get_global_rect().intersects(main.hud.toolbar_panel.get_global_rect()), "Deployment must not overlap the toolbar")
	main.hud.toggle_forces()
	expect(find_button(main.hud, "Road") != null, "Planning controls must expose Road")
	expect(find_button(main.hud, "Save Game") != null and find_button(main.hud, "Load Game") != null and find_button(main.hud, "Load Latest Autosave") != null, "Dedicated Game section must expose manual Save/Load and autosave recovery controls")
	expect(main.hud.save_button.is_visible_in_tree() and main.hud.load_button.is_visible_in_tree() and main.hud.load_autosave_button.is_visible_in_tree(), "Save and load controls must be visible to players, not just instantiated")
	expect(find_button(main.hud, "Utilities ▶") != null, "Construction categories must be collapsible")
	expect(find_button(main.hud, "Water Facility") != null, "Utility controls must remain reachable")
	expect(find_text(main.hud, "$") != null, "Resource bar must remain visible")

	var road := find_button(main.hud, "Road")
	road.pressed.emit()
	expect(main.interaction_mode == "Place Road", "Road button must enter placement mode")
	main.cancel_interaction()
	expect(main.interaction_mode.is_empty() and not main.missile_targeting, "Cancel must clear active UI mode")

	var missile_tile := find_land(main)
	select_building(main, missile_tile, CitySimulationScript.Building.MISSILE_SILO)
	expect(main.hud.selection_label.text.contains("Missile Silo"), "Missile Silo selection must show its exact name")
	expect(find_button(main.hud, "Manufacture Missile") != null and find_button(main.hud, "Target Missile (F10)") != null, "Missile Silo must expose missile actions")
	expect(find_button(main.hud, "Queue Infantry") == null and find_button(main.hud, "Start Next Research") == null and find_button(main.hud, "Order Selected Import") == null, "Missile Silo must hide unrelated actions")

	var sam_tile := find_land(main, [missile_tile])
	select_building(main, sam_tile, CitySimulationScript.Building.SAM_SITE)
	expect(main.hud.selection_label.text.contains("SAM Site") and main.hud.context_details_label.text.contains("Coverage"), "SAM selection must show operational coverage information")
	expect(find_button(main.hud, "Manufacture Missile") == null and find_button(main.hud, "Queue Infantry") == null and find_button(main.hud, "Start Next Research") == null, "SAM selection must hide silo, production, and research actions")

	var barracks := find_land(main, [missile_tile, sam_tile])
	select_building(main, barracks, CitySimulationScript.Building.BARRACKS)
	expect(find_button(main.hud, "Queue Infantry") != null and find_button(main.hud, "Queue Tank") == null, "Barracks must expose Infantry only")
	var vehicle := find_land(main, [missile_tile, sam_tile, barracks])
	select_building(main, vehicle, CitySimulationScript.Building.VEHICLE_FACTORY)
	expect(find_button(main.hud, "Queue Tank") != null and find_button(main.hud, "Queue Artillery") != null and find_button(main.hud, "Queue Infantry") == null, "Vehicle Factory must expose Tank and Artillery only")
	var drone := find_land(main, [missile_tile, sam_tile, barracks, vehicle])
	select_building(main, drone, CitySimulationScript.Building.DRONE_FACTORY)
	expect(find_button(main.hud, "Queue Recon Drone") != null and find_button(main.hud, "Queue Robot Unit") != null and find_button(main.hud, "Queue Tank") == null, "Drone Factory must expose Recon Drone and Robot only")
	var airbase := find_land(main, [missile_tile, sam_tile, barracks, vehicle, drone])
	select_building(main, airbase, CitySimulationScript.Building.AIRBASE)
	expect(find_button(main.hud, "Queue Fighter") != null and find_button(main.hud, "Queue Bomber") != null and find_button(main.hud, "Queue Tank") == null, "Airbase must expose Fighter and Bomber only")

	var depot := find_land(main, [missile_tile, sam_tile, barracks, vehicle, drone, airbase])
	select_building(main, depot, CitySimulationScript.Building.IMPORT_DEPOT)
	expect(find_button(main.hud, "Select import resource") != null and find_button(main.hud, "Order Selected Import") != null, "Import Depot must expose import controls")
	expect(find_button(main.hud, "Start Next Research") == null and find_button(main.hud, "Manufacture Missile") == null, "Import Depot must hide unrelated actions")
	var university := find_land(main, [missile_tile, sam_tile, barracks, vehicle, drone, airbase, depot])
	select_building(main, university, CitySimulationScript.Building.UNIVERSITY)
	expect(find_button(main.hud, "Start Next Research") != null and find_button(main.hud, "Order Selected Import") == null, "University must expose research only")
	var lab := find_land(main, [missile_tile, sam_tile, barracks, vehicle, drone, airbase, depot, university])
	select_building(main, lab, CitySimulationScript.Building.RESEARCH_LAB)
	expect(find_button(main.hud, "Start Next Research") != null, "Research Laboratory must expose research")

	var residential := find_land(main, [missile_tile, sam_tile, barracks, vehicle, drone, airbase, depot, university, lab])
	select_building(main, residential, CitySimulationScript.Building.RESIDENTIAL)
	expect(main.hud.selection_label.text == "Building selected: Residential", "Developed housing must retain its exact selection name")
	expect(main.hud.context_details_label.text.contains("Road:") and find_button(main.hud, "Queue Infantry") == null and find_button(main.hud, "Start Next Research") == null, "Residential selection must show services without unrelated actions")
	var commercial := find_land(main, [missile_tile, sam_tile, barracks, vehicle, drone, airbase, depot, university, lab, residential])
	select_building(main, commercial, CitySimulationScript.Building.COMMERCIAL)
	expect(main.hud.selection_label.text == "Building selected: Commercial", "Developed commerce must retain its exact selection name")
	expect(main.hud.context_details_label.text.contains("Jobs:") or main.hud.context_details_label.text.contains("Commercial"), "Commercial selection must show its identity and jobs")

	main.city.buildings[main.city.index(commercial)] = CitySimulationScript.Building.NONE
	main.city.zones[main.city.index(commercial)] = CitySimulationScript.Zone.NONE
	main.combat.clear_selection()
	main.selected_tile = find_land(main, [missile_tile, sam_tile, barracks, vehicle, drone, airbase, depot, university, lab, residential, commercial])
	main.hud.refresh()
	expect(main.hud.context_details_label.text.contains("Coordinates:") and find_button(main.hud, "Queue Infantry") == null and find_button(main.hud, "Start Next Research") == null, "Empty tile must show only tile information")
	main.selected_tile = Vector2i(-1, -1)
	main.hud.refresh()
	expect(main.hud.selection_label.text == "Nothing selected" and main.hud.context_details_label.text == "Nothing selected", "Clearing selection must remove stale contextual content")

	main.combat.spawn_developer_unit(1, CitySimulationScript.UnitType.INFANTRY, find_land(main))
	var unit_tile := find_land(main, [missile_tile, sam_tile, barracks, vehicle, drone, airbase, depot, university, lab, residential, commercial])
	main.combat.spawn_developer_unit(1, CitySimulationScript.UnitType.ARTILLERY, unit_tile)
	main.selected_tile = unit_tile
	main.combat.select_unit_at(unit_tile)
	main.hud.refresh()
	expect(find_button(main.hud, "Move") != null and find_button(main.hud, "Attack") != null and find_button(main.hud, "Defend") != null and find_button(main.hud, "Stop") != null, "Combat unit must expose Move, Attack, Defend, and Stop")
	expect(main.hud.command_panel.visible, "Selected player units must expose the lower command strip")
	expect(not main.hud.command_panel.get_global_rect().intersects(main.hud.toolbar_panel.get_global_rect()), "Unit commands must leave every toolbar category reachable")
	expect(not main.hud.command_panel.get_global_rect().intersects(main.hud.force_panel.get_global_rect()), "Unit commands must not cover deployment choices")
	expect(main.hud.context_details_label.text.contains("Artillery range"), "Artillery selection must show minimum and maximum range")
	expect(find_button(main.hud, "Queue Infantry") == null and find_button(main.hud, "Start Next Research") == null, "Combat unit must hide building actions")

	if failures.is_empty():
		print("UI validation passed: responsive construction, contextual selection, forces, and routed actions.")
	else:
		for failure in failures:
			push_error(failure)
	var result := 0 if failures.is_empty() else 1
	main.queue_free()
	main = null
	await process_frame
	await process_frame
	quit(result)

func select_building(main, tile: Vector2i, building_type: int) -> void:
	main.combat.clear_selection()
	main.selected_tile = tile
	main.city.buildings[main.city.index(tile)] = building_type
	main.hud.refresh()

func find_land(main, excluded: Array[Vector2i] = []) -> Vector2i:
	for y in main.map_data.size.y:
		for x in main.map_data.size.x:
			var tile := Vector2i(x, y)
			if main.map_data.is_land(tile) and not excluded.has(tile):
				return tile
	return Vector2i(-1, -1)

func find_button(node: Node, wanted: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == wanted:
			return child
		var nested := find_button(child, wanted)
		if nested != null:
			return nested
	return null

func find_text(node: Node, token: String) -> Label:
	for child in node.get_children():
		if child is Label and String((child as Label).text).contains(token):
			return child
		var nested := find_text(child, token)
		if nested != null:
			return nested
	return null
