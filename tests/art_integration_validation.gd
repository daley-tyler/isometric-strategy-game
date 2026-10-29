extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Iso = preload("res://scripts/iso_math.gd")
const Map = preload("res://scripts/map_data.gd")
const City = preload("res://scripts/city_simulation.gd")
const Art = preload("res://scripts/building_overlay.gd")
const Terrain = preload("res://scripts/terrain_detail_overlay.gd")
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	var main = Main.instantiate()
	root.add_child(main)
	main.set_process(false)
	await process_frame
	var data = main.map_data
	var city = main.city
	var kinds := {}
	for y in 128:
		for x in 128:
			var tile := Vector2i(x, y)
			kinds[data.get_terrain(tile)] = tile
			var edges := Terrain.edge_metadata(data, tile)
			for edge in edges.shared_edges:
				check(not edges.side_faces.has(edge) and not edges.shore_edges.has(edge), "Internal water edge generated wall or shoreline")
			check(edges == Terrain.edge_metadata(data, tile), "Adjacency must be deterministic")
			if data.is_bridge(tile): check(edges.bridge and data.is_traversable_ground(tile), "Bridge lost presentation/crossing state")
	var samples: Array[Vector2i] = [Vector2i.ZERO, Vector2i(127, 0), Vector2i(0, 127), Vector2i(127, 127)]
	for tile in kinds.values(): samples.append(tile)
	var ground := Vector2i(-1, -1)
	for y in range(4, 124):
		for x in range(4, 124):
			var tile := Vector2i(x, y)
			if city.building_site_reason(tile).is_empty(): ground = tile; break
		if ground.x >= 0: break
	city.roads[city.index(ground)] = 1
	samples.append(ground)
	var covered := ground + Vector2i(1, 0)
	city.buildings[city.index(covered)] = City.Building.POWER_PLANT
	samples.append(covered)
	for zoom in [0.35, 0.75, 2.25]:
		main.camera.zoom = Vector2.ONE * zoom
		for tile in samples:
			main.camera.position = Iso.tile_to_world(tile) + Vector2(7, -5)
			main.camera.force_update_scroll()
			for offset in [Vector2.ZERO, Vector2(24, 0), Vector2(-24, 0), Vector2(0, 12), Vector2(0, -12), Vector2(12, 7), Vector2(-12, 7), Vector2(12, -7), Vector2(-12, -7)]:
				var screen: Vector2 = main.get_global_transform_with_canvas() * (Iso.tile_to_world(tile) + offset)
				var motion := InputEventMouseMotion.new()
				motion.position = screen
				root.push_input(motion, true)
				check(main.hovered_tile == tile and main.hover_marker.displayed_tile == tile, "Viewport hover disagrees at %s zoom %s" % [tile, zoom])
			click(main, tile)
			check(main.selected_tile == tile and main.selection_marker.displayed_tile == tile, "Click/selection disagreement")
	check(main.hover_marker.z_index > 800 and main.selection_marker.z_index > 800, "Tile feedback hidden below sprites")
	check(main.hud.root_panel.size.y > 200 and main.hud.status_label.is_visible_in_tree(), "Placement feedback panel collapsed")
	city.buildings[city.index(covered)] = 0
	var money: float = city.resources[0]
	main.begin_placement("power", "Power Plant")
	point(main, ground)
	check(main.placement_preview.reason == "Cannot build: Road occupies tile", "Ghost must report road rejection")
	main.selected_tile = ground
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_3
	root.push_input(key, true)
	check(city.last_action_reason == main.placement_preview.reason and city.get_building(ground) == 0, "Keyboard bypassed preview validator")
	for kind in Art.BUILDING_CELLS:
		if kind in [City.Building.RESIDENTIAL, City.Building.COMMERCIAL]: continue
		check(city.building_placement_reason(ground, kind) == "Cannot build: Road occupies tile", "Building type bypasses road rule")
	var ai = main.ai_campaign.economy
	check(ai.building_placement_reason(ground, 1) == "Cannot build: Road occupies tile" and not ai.place_utility(ground, 1), "AI bypasses shared road occupancy")
	click(main, ground)
	check(city.resources[0] == money and city.get_building(ground) == 0, "Rejected road placement modified state")
	check(main.placement_preview.building_type == City.Building.POWER_PLANT, "Failed click should retain preview")
	city.roads[city.index(ground)] = 0
	point(main, ground)
	var footprint: Array[Vector2i] = main.placement_preview.footprint.duplicate()
	check(main.placement_preview.reason.is_empty() and footprint == [ground], "Valid preview footprint mismatch")
	click(main, ground)
	check(city.get_building(ground) == City.Building.POWER_PLANT and city.resources[0] == money - city.utility_cost(City.Building.POWER_PLANT), "Commit must match ghost and charge once")
	check(city.get_building_footprint_tiles(City.Building.POWER_PLANT, ground) == footprint, "Commit changed footprint")
	check(main.placement_preview.building_type == 0, "Successful placement left stale ghost")
	check(main.selected_tile == ground and main.selection_marker.displayed_tile == ground, "Committed tile not selected")
	check(not city.place_road(ground), "Road overwrote building")
	check(city.building_placement_reason(ground, 1) == "Cannot build: Existing building", "Existing building rejection missing")
	city.buildings[city.index(ground)] = 0
	city.rubble[city.index(ground)] = 1
	check(not city.place_utility(ground, 1), "Rubble accepted building")
	city.rubble[city.index(ground)] = 0
	for terrain_kind in [Map.Terrain.COAST, Map.Terrain.RIVER]:
		var tile: Vector2i = kinds[terrain_kind]
		var before: PackedFloat64Array = PackedFloat64Array(city.resources)
		check(city.building_placement_reason(tile, 1) == "Cannot build: Water" and not city.place_utility(tile, 1), "Water accepted building")
		check(PackedFloat64Array(city.resources) == before, "Failure spent resources")
	for kind in Art.BUILDING_CELLS:
		var art := Art.sprite_metadata(ground, kind, data.seed)
		check((art.target.position + art.foot * art.scale).is_equal_approx(Iso.tile_to_world(ground)), "Sprite foot detached from tile")
		check(Iso.sprite_depth(ground + Vector2i(1, 0)) > Iso.sprite_depth(ground), "Depth must follow feet")
	main.begin_placement("water", "Water Facility")
	main.cancel_interaction()
	check(main.placement_preview.building_type == 0, "Cancel left ghost")
	if OS.get_cmdline_user_args().has("--capture"):
		main.camera.zoom = Vector2(1.5, 1.5)
		point(main, ground)
		city.buildings[city.index(ground)] = City.Building.WATER_FACILITY
		main.world_renderer.refresh_tile(ground)
		main.world_renderer.update_visibility(main.camera)
		main.begin_placement("power", "Power Plant")
		main.set_hover_world(Iso.tile_to_world(ground + Vector2i(1, 0)))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/city-art-placement.png")
		main.cancel_interaction()
		point(main, kinds[Map.Terrain.RIVER])
		main.world_renderer.update_visibility(main.camera)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/city-art-water.png")
	if failures.is_empty(): print("Art integration validation passed: viewport picking, ghost/commit, occupancy, anchors and water adjacency.")
	for failure in failures: push_error(failure)
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func point(main, tile: Vector2i) -> void:
	main.camera.position = Iso.tile_to_world(tile)
	main.camera.force_update_scroll()
	var event := InputEventMouseMotion.new()
	event.position = main.get_global_transform_with_canvas() * Iso.tile_to_world(tile)
	root.push_input(event, true)

func click(main, tile: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = main.get_global_transform_with_canvas() * Iso.tile_to_world(tile)
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
