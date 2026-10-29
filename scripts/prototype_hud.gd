class_name PrototypeHud
extends CanvasLayer

const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const CityConfigScript = preload("res://scripts/city_config.gd")
const CombatConfigScript = preload("res://scripts/combat_config.gd")
const StrategicConfigScript = preload("res://scripts/strategic_config.gd")

var main
var resources_label := Label.new()
var mode_label := Label.new()
var selection_label := Label.new()
var status_label := Label.new()
var root_panel := Panel.new()
var context_container := VBoxContainer.new()
var context_details_label: Label
var context_buttons: Array[Button] = []
var forces_buttons: Array[Button] = []
var current_context_key := ""
var scroll: ScrollContainer
var victory_panel := Panel.new()
var victory_title_label := Label.new()
var victory_summary_label := Label.new()
var continue_sandbox_button := Button.new()
var restart_button := Button.new()
var defeat_load_button := Button.new()
var save_button := Button.new()
var load_button := Button.new()
var load_autosave_button := Button.new()
var toolbar_panel := Panel.new()
var palette_panel := Panel.new()
var command_panel := Panel.new()
var force_panel := Panel.new()
var force_view_buttons: Array[Button] = []
var palette_title := Label.new()
var palette_content := VBoxContainer.new()
var selected_palette := ""
var legacy_start := 0

func _exit_tree() -> void:
	# Release script-held references when a headless validation scene is torn down.
	context_buttons.clear()
	forces_buttons.clear()
	main = null
	context_details_label = null
	scroll = null

func configure(owner) -> void:
	main = owner
	layer = 10
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)

	var bar := Panel.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.offset_left = 12.0
	bar.offset_right = -12.0
	bar.offset_top = 10.0
	bar.offset_bottom = 52.0
	canvas.add_child(bar)
	resources_label.anchor_right = 1.0
	resources_label.offset_left = 10.0
	resources_label.offset_right = -10.0
	resources_label.offset_top = 5.0
	resources_label.offset_bottom = -5.0
	resources_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resources_label.add_theme_font_size_override("font_size", 12)
	bar.add_child(resources_label)

	root_panel.anchor_left = 1.0
	root_panel.anchor_right = 1.0
	root_panel.anchor_bottom = 1.0
	root_panel.offset_left = -308.0
	root_panel.offset_right = -10.0
	root_panel.offset_top = 62.0
	root_panel.offset_bottom = -94.0
	canvas.add_child(root_panel)
	scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8.0
	scroll.offset_top = 8.0
	scroll.offset_right = -8.0
	scroll.offset_bottom = -8.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size = Vector2(0, 0)
	scroll.add_child(column)

	mode_label.add_theme_color_override("font_color", Color("ffe28a"))
	column.add_child(mode_label)
	var cancel := Button.new()
	cancel.text = "Cancel / Esc"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(main.cancel_interaction)
	column.add_child(cancel)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("ffb9a8"))
	column.add_child(status_label)
	column.add_child(HSeparator.new())

	add_section(column, "Selected Object")
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(selection_label)
	context_container.add_theme_constant_override("separation", 3)
	column.add_child(context_container)
	column.add_child(HSeparator.new())

	legacy_start = column.get_child_count()
	add_section(column, "Construction")
	var construction_root := VBoxContainer.new()
	construction_root.add_theme_constant_override("separation", 2)
	column.add_child(construction_root)
	add_collapsible_section(construction_root, "Planning", [
		["Road", "road"], ["Residential Zone", "residential"], ["Commercial Zone", "commercial"], ["Bulldoze", "bulldoze"]], true)
	add_collapsible_section(construction_root, "Utilities", [
		["Power Plant", "power"], ["Water Facility", "water"], ["Fire Station", "fire"]], false)
	add_collapsible_section(construction_root, "Industry", [
		["Farm", "farm"], ["Materials Plant", "materials"], ["Refinery", "refinery"], ["Import Depot", "import"], ["Defense Factory", "defense"]], false)
	add_collapsible_section(construction_root, "Research", [
		["University", "university"], ["Research Laboratory", "lab"]], false)
	add_collapsible_section(construction_root, "Military", [
		["Barracks", "barracks"], ["Vehicle Factory", "vehicle"], ["Drone Factory", "drone"], ["Airbase", "airbase"], ["SAM Site", "sam"], ["Missile Silo", "silo"]], false)
	column.add_child(HSeparator.new())

	add_section(column, "Available Forces")
	var forces_hint := Label.new()
	forces_hint.text = "Deploy from a capital or matching facility"
	forces_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(forces_hint)
	for unit_type in range(CitySimulationScript.UnitType.INFANTRY, CitySimulationScript.UnitType.FIGHTER + 1):
		var deploy_button := Button.new()
		deploy_button.pressed.connect(main.hud_deploy_unit.bind(unit_type))
		column.add_child(deploy_button)
		forces_buttons.append(deploy_button)
	column.add_child(HSeparator.new())
	var game_section_start := column.get_child_count()
	add_section(column, "Game")
	save_button.text = "Save Game"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(main.hud_save_game)
	column.add_child(save_button)
	load_button.text = "Load Game"
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(main.hud_load_game)
	column.add_child(load_button)
	load_autosave_button.text = "Load Latest Autosave"
	load_autosave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_autosave_button.pressed.connect(main.hud_load_latest_autosave)
	column.add_child(load_autosave_button)
	column.add_child(HSeparator.new())
	add_section(column, "Controls")
	var controls := Label.new()
	controls.text = "WASD / arrows pan · middle drag · wheel or +/- zoom\nClick selects · Esc cancels active modes"
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(controls)
	# Compact palettes replace construction and deployment, while save/load
	# and controls remain accessible in the contextual sidebar.
	for child_index in range(legacy_start, game_section_start):
		column.get_child(child_index).visible = false
	build_compact_controls(canvas)

	victory_panel.anchor_left = 0.5
	victory_panel.anchor_top = 0.5
	victory_panel.anchor_right = 0.5
	victory_panel.anchor_bottom = 0.5
	victory_panel.offset_left = -270.0
	victory_panel.offset_top = -190.0
	victory_panel.offset_right = 270.0
	victory_panel.offset_bottom = 190.0
	victory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_panel.z_index = 20
	victory_panel.visible = false
	canvas.add_child(victory_panel)
	var victory_margin := MarginContainer.new()
	victory_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_margin.add_theme_constant_override("margin_left", 28)
	victory_margin.add_theme_constant_override("margin_top", 24)
	victory_margin.add_theme_constant_override("margin_right", 28)
	victory_margin.add_theme_constant_override("margin_bottom", 24)
	victory_panel.add_child(victory_margin)
	var victory_column := VBoxContainer.new()
	victory_column.add_theme_constant_override("separation", 12)
	victory_margin.add_child(victory_column)
	victory_title_label.text = "VICTORY — REGIONAL UNIFICATION"
	victory_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_title_label.add_theme_font_size_override("font_size", 24)
	victory_title_label.add_theme_color_override("font_color", Color("ffe28a"))
	victory_column.add_child(victory_title_label)
	victory_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	victory_summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	victory_column.add_child(victory_summary_label)
	continue_sandbox_button.text = "Continue in Sandbox"
	continue_sandbox_button.custom_minimum_size.y = 48.0
	continue_sandbox_button.pressed.connect(main.hud_continue_sandbox)
	victory_column.add_child(continue_sandbox_button)
	defeat_load_button.text = "Load Latest Autosave"
	defeat_load_button.custom_minimum_size.y = 40.0
	defeat_load_button.pressed.connect(main.hud_load_latest_autosave)
	victory_column.add_child(defeat_load_button)
	restart_button.text = "Restart Prototype"
	restart_button.custom_minimum_size.y = 40.0
	restart_button.pressed.connect(main.hud_restart_prototype)
	victory_column.add_child(restart_button)
	refresh()

func build_compact_controls(canvas: Control) -> void:
	toolbar_panel.anchor_top = 1.0
	toolbar_panel.anchor_bottom = 1.0
	toolbar_panel.offset_left = 12.0
	toolbar_panel.offset_right = 614.0
	toolbar_panel.offset_top = -78.0
	toolbar_panel.offset_bottom = -12.0
	toolbar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(toolbar_panel)
	var toolbar := HBoxContainer.new()
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toolbar.offset_left = 7.0; toolbar.offset_top = 7.0; toolbar.offset_right = -7.0; toolbar.offset_bottom = -7.0
	toolbar.add_theme_constant_override("separation", 4)
	toolbar_panel.add_child(toolbar)
	for entry in [["▤", "Planning"], ["⌂", "Zones"], ["ϟ", "Utilities"], ["▦", "Industry"], ["⌬", "Research"], ["▲", "Military"], ["✕", "Bulldoze"]]:
		var button := Button.new()
		button.text = "%s\n%s" % [entry[0], entry[1]]
		button.tooltip_text = "Open %s tools" % entry[1]
		button.custom_minimum_size = Vector2(70, 48)
		button.pressed.connect(open_palette.bind(String(entry[1])))
		toolbar.add_child(button)
	var forces := Button.new()
	forces.text = "♟\nForces"
	forces.tooltip_text = "Produced unit inventory and deployment"
	forces.custom_minimum_size = Vector2(70, 48)
	forces.pressed.connect(toggle_forces)
	toolbar.add_child(forces)

	palette_panel.anchor_top = 1.0
	palette_panel.anchor_bottom = 1.0
	palette_panel.offset_left = 12.0; palette_panel.offset_right = 340.0
	palette_panel.offset_top = -440.0; palette_panel.offset_bottom = -156.0
	palette_panel.visible = false
	palette_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(palette_panel)
	var palette_scroll := ScrollContainer.new()
	palette_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	palette_panel.add_child(palette_scroll)
	var palette_margin := MarginContainer.new()
	palette_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	palette_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_margin.add_theme_constant_override("margin_left", 10); palette_margin.add_theme_constant_override("margin_right", 10)
	palette_margin.add_theme_constant_override("margin_top", 8); palette_margin.add_theme_constant_override("margin_bottom", 8)
	palette_scroll.add_child(palette_margin)
	var palette_column := VBoxContainer.new()
	palette_margin.add_child(palette_column)
	palette_title.add_theme_color_override("font_color", Color("9fd5ff"))
	palette_column.add_child(palette_title)
	palette_content.add_theme_constant_override("separation", 3)
	palette_column.add_child(palette_content)

	force_panel.anchor_top = 1.0; force_panel.anchor_bottom = 1.0
	force_panel.offset_left = 350.0; force_panel.offset_right = 620.0
	force_panel.offset_top = -476.0; force_panel.offset_bottom = -156.0
	force_panel.visible = false; force_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(force_panel)
	var force_scroll := ScrollContainer.new()
	force_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	force_scroll.offset_left = 10; force_scroll.offset_top = 8; force_scroll.offset_right = -10; force_scroll.offset_bottom = -8
	force_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	force_panel.add_child(force_scroll)
	var force_column := VBoxContainer.new()
	force_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	force_scroll.add_child(force_column)
	var force_title := Label.new(); force_title.text = "♟ AVAILABLE FORCES"; force_title.add_theme_color_override("font_color", Color("9fd5ff")); force_column.add_child(force_title)
	for unit_type in range(CitySimulationScript.UnitType.INFANTRY, CitySimulationScript.UnitType.FIGHTER + 1):
		var deploy := Button.new(); deploy.pressed.connect(main.hud_deploy_unit.bind(unit_type)); force_column.add_child(deploy); force_view_buttons.append(deploy)

	command_panel.anchor_left = 0.5; command_panel.anchor_right = 0.5
	command_panel.anchor_top = 1.0; command_panel.anchor_bottom = 1.0
	command_panel.offset_left = -190; command_panel.offset_right = 190; command_panel.offset_top = -148; command_panel.offset_bottom = -86
	command_panel.visible = false; command_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(command_panel)
	var commands := HBoxContainer.new(); commands.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); commands.offset_left = 8; commands.offset_top = 8; commands.offset_right = -8; commands.offset_bottom = -8; command_panel.add_child(commands)
	for entry in [["➜ Move", "move"], ["◎ Attack", "attack"], ["⬡ Defend", "defend"], ["■ Stop", "stop"]]:
		var command := Button.new(); command.text = entry[0]; command.tooltip_text = "%s selected unit" % entry[1].capitalize(); command.pressed.connect(main.hud_command.bind(entry[1])); commands.add_child(command)

func open_palette(category: String) -> void:
	force_panel.visible = false
	if category == "Bulldoze":
		main.begin_placement("bulldoze", "Bulldoze")
		palette_panel.visible = false
		return
	selected_palette = category
	palette_panel.visible = true
	palette_title.text = "%s TOOLS" % category.to_upper()
	for child in palette_content.get_children():
		palette_content.remove_child(child); child.queue_free()
	var entries := palette_entries(category)
	for entry in entries:
		add_palette_tool(String(entry[0]), String(entry[1]), String(entry[2]), int(entry[3]))

func palette_entries(category: String) -> Array:
	match category:
		"Planning": return [["▤ Road", "road", "Road access", 0]]
		"Zones": return [["⌂ Residential", "residential", "Housing zone", 0], ["▥ Commercial", "commercial", "Jobs and commerce", 0]]
		"Utilities": return [["ϟ Power Plant", "power", "$%d · electricity" % CityConfigScript.POWER_PLANT_COST, 0], ["◉ Water Facility", "water", "$%d · water" % CityConfigScript.WATER_FACILITY_COST, 0], ["♨ Fire Station", "fire", "$%d · coverage" % CityConfigScript.FIRE_STATION_COST, 0]]
		"Industry": return [["≋ Farm", "farm", "Food production", CitySimulationScript.Technology.NONE], ["▦ Materials Plant", "materials", "Iron/Stone required", CitySimulationScript.Technology.INDUSTRIAL_EXPANSION], ["◌ Refinery", "refinery", "Oil required", CitySimulationScript.Technology.REFINING], ["▣ Import Depot", "import", "Paid resource imports", CitySimulationScript.Technology.NONE], ["⬒ Defense Factory", "defense", "Military supplies", CitySimulationScript.Technology.DEFENSE_INDUSTRY]]
		"Research": return [["▤ University", "university", "Starts research", CitySimulationScript.Technology.NONE], ["⌬ Research Lab", "lab", "Advanced research", CitySimulationScript.Technology.INDUSTRIAL_EXPANSION]]
		"Military": return [["▲ Barracks", "barracks", "Infantry", CitySimulationScript.Technology.NONE], ["▰ Vehicle Factory", "vehicle", "Tanks and artillery", CitySimulationScript.Technology.ADVANCED_MANUFACTURING], ["✣ Drone Factory", "drone", "Recon and robots", CitySimulationScript.Technology.AUTOMATION], ["✈ Airbase", "airbase", "Fighters and bombers", CitySimulationScript.Technology.AEROSPACE], ["◉ SAM Site", "sam", "Air defense", CitySimulationScript.Technology.NEAR_FUTURE], ["▲ Missile Silo", "silo", "Strategic missiles", CitySimulationScript.Technology.NEAR_FUTURE]]
	return []

func add_palette_tool(title: String, tool: String, hint: String, technology: int) -> void:
	var button := Button.new()
	var locked: bool = technology != CitySimulationScript.Technology.NONE and not main.city.is_technology_unlocked(technology)
	button.text = title + ("  🔒" if locked else "")
	button.tooltip_text = ("Requires %s" % main.city.technology_name(technology)) if locked else hint
	button.disabled = locked
	button.pressed.connect(main.begin_placement.bind(tool, title.trim_prefix(title.split(" ")[0] + " ")))
	palette_content.add_child(button)

func toggle_forces() -> void:
	palette_panel.visible = false
	force_panel.visible = not force_panel.visible

func add_section(column: VBoxContainer, title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", Color("b7d8ff"))
	column.add_child(label)

func add_collapsible_section(parent: VBoxContainer, title: String, entries: Array, expanded: bool) -> void:
	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = expanded
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(header)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(content)
	for entry in entries:
		var button := Button.new()
		button.text = String(entry[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(main.begin_placement.bind(String(entry[1]), String(entry[0])))
		content.add_child(button)
	header.toggled.connect(set_section_state.bind(header, content, title))
	set_section_state(expanded, header, content, title)

func set_section_state(expanded: bool, header: Button, content: VBoxContainer, title: String) -> void:
	header.text = title + (" ▼" if expanded else " ▶")
	content.visible = expanded

func refresh() -> void:
	if main == null:
		return
	var city = main.city
	resources_label.text = "$ %.0f   ♟ %d   ⚒ %d   ϟ %.1f   ≋ %.0f   ◈ %.0f   ◌ %.0f   ▲ %.0f" % [city.get_resource(CitySimulationScript.LedgerResource.MONEY), city.occupied_households, city.employed_workforce, city.get_resource(CitySimulationScript.LedgerResource.ELECTRICITY), city.get_resource(CitySimulationScript.LedgerResource.FOOD), city.get_resource(CitySimulationScript.LedgerResource.MATERIALS), city.get_resource(CitySimulationScript.LedgerResource.FUEL), city.get_resource(CitySimulationScript.LedgerResource.MILITARY_SUPPLIES)]
	mode_label.text = "Mode: %s" % (main.interaction_mode if not main.interaction_mode.is_empty() else "Select")
	status_label.text = "Status: %s" % main.action_feedback if not main.action_feedback.is_empty() else "Status: Ready"
	if main.placement_preview != null and main.placement_building_type() != 0:
		status_label.text = main.placement_preview.reason if not main.placement_preview.reason.is_empty() else "Click to build at %s" % main.hovered_tile
	var context_key := context_identity()
	if context_key != current_context_key:
		current_context_key = context_key
		rebuild_contextual_content()
	selection_label.text = context_heading()
	context_details_label.text = context_details()
	refresh_forces()
	refresh_force_view()
	refresh_command_bar()
	refresh_campaign_overlay()

func refresh_campaign_overlay() -> void:
	var show_outcome: bool = main.campaign != null and main.campaign.is_outcome_pending()
	var defeat: bool = show_outcome and main.campaign.is_defeat_pending()
	root_panel.visible = not show_outcome
	if show_outcome and not victory_panel.visible:
		var stats: Dictionary = main.campaign.victory_stats
		var elapsed: int = roundi(float(stats.get("elapsed_seconds", 0.0)))
		victory_title_label.text = "DEFEAT — CAPITAL LOST" if defeat else "VICTORY — REGIONAL UNIFICATION"
		victory_summary_label.text = "Your capital was captured at %s.\n\nElapsed: %02d:%02d\nSurviving forces: %d player · %d enemy\n\nLoad an autosave or restart the deterministic prototype." % [main.campaign.defeated_capital, elapsed / 60, elapsed % 60, int(stats.get("player_forces", 0)), int(stats.get("enemy_forces", 0))] if defeat else "%s defeated\nCapital captured at %s\n\nElapsed: %02d:%02d\nPopulation: %d\nMoney: $%.0f\nFood: %.0f · Materials: %.0f · Fuel: %.0f\nMilitary supplies: %.0f\nSurviving forces: %d player · %d enemy\n\nThe world is intact. Continue building and fighting in sandbox mode." % [main.campaign.defeated_nation, main.campaign.defeated_capital, elapsed / 60, elapsed % 60, int(stats.get("population", 0)), float(stats.get("money", 0.0)), float(stats.get("food", 0.0)), float(stats.get("materials", 0.0)), float(stats.get("fuel", 0.0)), int(stats.get("military_supplies", 0.0)), int(stats.get("player_forces", 0)), int(stats.get("enemy_forces", 0))]
		continue_sandbox_button.visible = not defeat
		defeat_load_button.visible = defeat
		restart_button.visible = defeat
		( defeat_load_button if defeat else continue_sandbox_button).grab_focus()
	victory_panel.visible = show_outcome

func context_identity() -> String:
	var unit_id: int = main.combat.selected_unit_id
	var unit: Dictionary = main.combat.get_unit(unit_id)
	if unit_id >= 0 and not unit.is_empty() and bool(unit.get("alive", false)):
		return "unit:%d" % unit_id
	if not main.map_data.is_valid(main.selected_tile):
		return "none"
	var building: int = main.city.get_building(main.selected_tile)
	if building != CitySimulationScript.Building.NONE:
		return "building:%d:%s" % [building, main.selected_tile]
	var zone: int = main.city.get_zone(main.selected_tile)
	if zone != CitySimulationScript.Zone.NONE:
		return "zone:%d:%s" % [zone, main.selected_tile]
	return "tile:%s" % main.selected_tile

func rebuild_contextual_content() -> void:
	for child in context_container.get_children():
		context_container.remove_child(child)
		child.free()
	context_details_label = Label.new()
	context_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_container.add_child(context_details_label)
	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_container.add_child(actions)
	context_buttons.clear()
	var kind := context_identity().split(":")[0]
	if kind == "unit":
		add_context_button(actions, "Move", main.hud_command.bind("move"))
		add_context_button(actions, "Attack", main.hud_command.bind("attack"))
		add_context_button(actions, "Defend", main.hud_command.bind("defend"))
		add_context_button(actions, "Stop", main.hud_command.bind("stop"))
		return
	if kind != "building":
		return
	var building: int = main.city.get_building(main.selected_tile)
	match building:
		CitySimulationScript.Building.BARRACKS:
			add_production_button(actions, CitySimulationScript.UnitType.INFANTRY)
		CitySimulationScript.Building.VEHICLE_FACTORY:
			add_production_button(actions, CitySimulationScript.UnitType.TANK)
			add_production_button(actions, CitySimulationScript.UnitType.ARTILLERY)
		CitySimulationScript.Building.DRONE_FACTORY:
			add_production_button(actions, CitySimulationScript.UnitType.RECON_DRONE)
			add_production_button(actions, CitySimulationScript.UnitType.ROBOT_UNIT)
		CitySimulationScript.Building.AIRBASE:
			add_production_button(actions, CitySimulationScript.UnitType.FIGHTER)
			add_production_button(actions, CitySimulationScript.UnitType.BOMBER)
		CitySimulationScript.Building.IMPORT_DEPOT:
			var select_import := Button.new()
			select_import.text = "Select import resource"
			select_import.pressed.connect(main.hud_cycle_import)
			actions.add_child(select_import)
			context_buttons.append(select_import)
			add_context_button(actions, "Order Selected Import", main.hud_order_import)
		CitySimulationScript.Building.UNIVERSITY, CitySimulationScript.Building.RESEARCH_LAB:
			add_context_button(actions, "Start Next Research", main.hud_start_research)
		CitySimulationScript.Building.MISSILE_SILO:
			add_context_button(actions, "Manufacture Missile", main.hud_manufacture_missile)
			add_context_button(actions, "Target Missile (F10)", main.hud_target_missile)

func add_context_button(parent: VBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	context_buttons.append(button)
	return button

func add_production_button(parent: VBoxContainer, unit_type: int) -> void:
	var city = main.city
	var button := add_context_button(parent, "Queue %s" % city.unit_name(unit_type), main.hud_queue_unit.bind(unit_type))
	button.tooltip_text = "Manufacture this unit at the selected facility"

func refresh_forces() -> void:
	var building: int = main.city.get_building(main.selected_tile)
	for i in forces_buttons.size():
		var unit_type := i + CitySimulationScript.UnitType.INFANTRY
		var definition: Dictionary = main.city.unit_definition(unit_type)
		var count: int = main.city.get_produced_unit_count(unit_type)
		var required: int = int(definition.get("facility", -1))
		var deployable: bool = main.selected_tile == main.map_data.player_capital or building == required
		forces_buttons[i].text = "%s x%d  [Deploy]" % [String(definition.get("name", "Unit")), count]
		forces_buttons[i].disabled = count <= 0 or not deployable

func refresh_force_view() -> void:
	var building: int = main.city.get_building(main.selected_tile)
	for i in force_view_buttons.size():
		var unit_type := i + CitySimulationScript.UnitType.INFANTRY
		var definition: Dictionary = main.city.unit_definition(unit_type)
		var count: int = main.city.get_produced_unit_count(unit_type)
		var required: int = int(definition.get("facility", -1))
		var deployable: bool = main.selected_tile == main.map_data.player_capital or building == required
		force_view_buttons[i].text = "%s  x%d  Deploy" % [String(definition.get("name", "Unit")), count]
		force_view_buttons[i].disabled = count <= 0 or not deployable
		force_view_buttons[i].tooltip_text = "Select the capital or matching facility to deploy"

func refresh_command_bar() -> void:
	var unit: Dictionary = main.combat.get_unit(main.combat.selected_unit_id)
	command_panel.visible = not unit.is_empty() and bool(unit.get("alive", false)) and int(unit.get("owner", 0)) == CombatConfigScript.OWNER_PLAYER and not (main.campaign != null and main.campaign.is_outcome_pending())

func context_heading() -> String:
	var unit_id: int = main.combat.selected_unit_id
	var unit: Dictionary = main.combat.get_unit(unit_id)
	if unit_id >= 0 and not unit.is_empty() and bool(unit.get("alive", false)):
		return "Unit selected"
	if not main.map_data.is_valid(main.selected_tile):
		return "Nothing selected"
	var building: int = main.city.get_building(main.selected_tile)
	if building != CitySimulationScript.Building.NONE:
		return "Building selected: %s" % main.city.building_name(building)
	var zone: int = main.city.get_zone(main.selected_tile)
	if zone == CitySimulationScript.Zone.RESIDENTIAL:
		return "Residential zone selected"
	if zone == CitySimulationScript.Zone.COMMERCIAL:
		return "Commercial zone selected"
	return "Tile selected"

func context_details() -> String:
	var unit_id: int = main.combat.selected_unit_id
	var unit: Dictionary = main.combat.get_unit(unit_id)
	if unit_id >= 0 and not unit.is_empty() and bool(unit.get("alive", false)):
		return unit_details(unit)
	if not main.map_data.is_valid(main.selected_tile):
		return "Nothing selected"
	var building: int = main.city.get_building(main.selected_tile)
	if building == CitySimulationScript.Building.RESIDENTIAL or building == CitySimulationScript.Building.COMMERCIAL or main.city.get_zone(main.selected_tile) != CitySimulationScript.Zone.NONE:
		var zone_name := "Residential" if main.city.get_zone(main.selected_tile) == CitySimulationScript.Zone.RESIDENTIAL or building == CitySimulationScript.Building.RESIDENTIAL else "Commercial"
		var summary := "%s\n%s" % [zone_name, main.city.selection_summary(main.selected_tile)]
		var blocker: String = main.city.shortage_reason(main.selected_tile)
		if not blocker.is_empty():
			summary += "\nBlocker: %s" % blocker
		return summary
	if building != CitySimulationScript.Building.NONE:
		return building_details(building)
	return tile_details()

func building_details(building: int) -> String:
	var city = main.city
	var lines: Array[String] = ["Owner: Player", "Road: %s" % ("Connected" if city.has_road_access(main.selected_tile) else "No access")]
	if building == CitySimulationScript.Building.POWER_PLANT:
		lines.append("Power: Generation · %.0f capacity" % CityConfigScript.POWER_CAPACITY)
	else:
		lines.append("Power: %s" % ("Connected" if city.has_power(main.selected_tile) else "No power"))
	if building == CitySimulationScript.Building.SAM_SITE:
		lines.append("Operational: %s" % ("Yes" if main.strategic.sam_operational(main.selected_tile) else "No"))
		lines.append("Coverage: %d tiles · cooldown %d" % [StrategicConfigScript.SAM_RANGE, int(main.strategic.sam_cooldowns.get(main.selected_tile, 0))])
	elif building == CitySimulationScript.Building.MISSILE_SILO:
		lines.append(main.strategic.silo_summary(main.selected_tile))
	elif building == CitySimulationScript.Building.WATER_FACILITY or building == CitySimulationScript.Building.FIRE_STATION:
		lines.append("Water: %s" % ("Connected" if city.has_water(main.selected_tile) else "No water"))
		lines.append("Fire: %s" % ("Covered" if city.has_fire_coverage(main.selected_tile) else "Not covered"))
	else:
		lines.append("Water: %s" % ("Connected" if city.has_water(main.selected_tile) else "No water"))
		lines.append("Fire: %s" % ("Covered" if city.has_fire_coverage(main.selected_tile) else "Not covered"))
	var definition: Dictionary = city.building_definition(building)
	if definition.has("output"):
		lines.append("Output: %s +%.1f/tick" % [city.resource_name(int(definition["output"])), float(definition.get("rate", 0.0))])
	if definition.has("deposit"):
		var deposit_requirement := deposit_requirement_text(definition["deposit"])
		var deposit_state := "Available" if city.has_required_deposit(main.selected_tile, definition["deposit"]) else "Missing"
		lines.append("Deposit: %s (%s)" % [deposit_state, deposit_requirement])
	if building == CitySimulationScript.Building.IMPORT_DEPOT:
		lines.append(city.import_summary())
	if building == CitySimulationScript.Building.UNIVERSITY or building == CitySimulationScript.Building.RESEARCH_LAB:
		lines.append("Research: %s" % city.research_status)
		lines.append("Progress: %.1f · Rate %.1f/tick" % [city.research_progress, float(definition.get("research_rate", 0.0))])
	if building == CitySimulationScript.Building.BARRACKS or building == CitySimulationScript.Building.VEHICLE_FACTORY or building == CitySimulationScript.Building.DRONE_FACTORY or building == CitySimulationScript.Building.AIRBASE:
		lines.append("Production: %s" % city.get_building_status(main.selected_tile))
	return "\n".join(lines)

func unit_details(unit: Dictionary) -> String:
	var unit_type := int(unit["type"])
	var owner := "Player" if int(unit["owner"]) == CombatConfigScript.OWNER_PLAYER else "AI"
	var lines: Array[String] = ["%s\nOwner: %s\nHealth: %.0f/%.0f\nOrder: %s" % [String(CombatConfigScript.UNIT_DATA[unit_type]["name"]), owner, float(unit["health"]), float(unit["max_health"]), CombatConfigScript.command_name(int(unit["command"]))]]
	var target_text := unit_target_text(unit)
	if not target_text.is_empty():
		lines.append(target_text)
	lines.append("Range: %d · Cooldown: %d" % [int(unit.get("range", 0)), int(unit.get("weapon_cooldown", 0))])
	if unit_type == CitySimulationScript.UnitType.ARTILLERY:
		lines.append("Artillery range: %d–%d" % [CombatConfigScript.ARTILLERY_MIN_RANGE, CombatConfigScript.ARTILLERY_MAX_RANGE])
	return "\n".join(lines)

func unit_target_text(unit: Dictionary) -> String:
	var command := int(unit.get("command", CombatConfigScript.COMMAND_IDLE))
	if command == CombatConfigScript.COMMAND_MOVE and not Array(unit.get("path", [])).is_empty():
		return "Destination: %s" % Array(unit["path"])[-1]
	var target_id := int(unit.get("target_id", -1))
	if target_id >= 0:
		var target: Dictionary = main.combat.get_unit(target_id)
		if not target.is_empty():
			return "Target: %s" % target.get("tile", "unknown")
	if unit.has("target_tile"):
		return "Target: %s" % unit["target_tile"]
	return ""

func tile_details() -> String:
	var tile: Vector2i = main.selected_tile
	var territory := "Neutral"
	if tile == main.map_data.player_capital:
		territory = "Player capital"
	elif tile == main.map_data.ai_capital:
		territory = "AI capital"
	elif main.combat.territory[main.map_data.index(tile)] == CombatConfigScript.OWNER_PLAYER:
		territory = "Player territory"
	elif main.combat.territory[main.map_data.index(tile)] == CombatConfigScript.OWNER_AI:
		territory = "AI territory"
	var road := "Yes" if main.city.has_road(tile) else "No"
	var zone := "None"
	if main.city.get_zone(tile) == CitySimulationScript.Zone.RESIDENTIAL:
		zone = "Residential"
	elif main.city.get_zone(tile) == CitySimulationScript.Zone.COMMERCIAL:
		zone = "Commercial"
	var deposit: String = main.city.deposit_name(main.map_data.get_resource_deposit(tile))
	return "Coordinates: %s\nTerrain: %s\nOwnership: %s\nRoad: %s · Zone: %s\nDeposit: %s" % [tile, terrain_name(main.map_data.get_terrain(tile)), territory, road, zone, deposit]

func terrain_name(terrain: int) -> String:
	return ["Plains", "Forest", "Hill", "River", "Coast"][clampi(terrain, 0, 4)]

func deposit_requirement_text(accepted: Array) -> String:
	var names: Array[String] = []
	for deposit in accepted:
		names.append(main.city.deposit_name(int(deposit)))
	return "/".join(names) + " nearby"
