extends SceneTree

const IsoMathScript = preload("res://scripts/iso_math.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const WorldRendererScript = preload("res://scripts/world_renderer.gd")
const ChunkRendererScript = preload("res://scripts/chunk_renderer.gd")
const BuildingOverlayScript = preload("res://scripts/building_overlay.gd")
const TerrainDetailOverlayScript = preload("res://scripts/terrain_detail_overlay.gd")
const CombatRendererScript = preload("res://scripts/combat_renderer.gd")
const MainScene = preload("res://scenes/main.tscn")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")

var failures: Array[String] = []

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _init() -> void:
	call_deferred("run_validation")

func run_validation() -> void:
	validate_coordinate_round_trips()
	validate_tile_selection()
	validate_map_generation()
	validate_world_features()
	validate_river_continuity()
	validate_capitals_and_queries()
	validate_marker_placement()
	validate_city_simulation()
	validate_city_feedback()
	validate_visual_assets()
	validate_chunks_and_culling()
	validate_main_scene_initialization()
	if failures.is_empty():
		print("Foundation validation passed: coordinate conversion, tile selection, deterministic map generation.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func validate_coordinate_round_trips() -> void:
	for tile in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(63, 64), Vector2i(127, 127)]:
		expect(IsoMathScript.world_to_tile(IsoMathScript.tile_to_world(tile), MapDataScript.MAP_SIZE) == tile, "Coordinate round trip failed for %s" % tile)

func validate_tile_selection() -> void:
	var sample := Vector2i(42, 77)
	var center := IsoMathScript.tile_to_world(sample)
	for offset in [Vector2(0, 0), Vector2(0, -12), Vector2(20, 0), Vector2(-20, 0), Vector2(0, 12)]:
		expect(IsoMathScript.world_to_tile(center + offset, MapDataScript.MAP_SIZE) == sample, "Diamond selection failed at %s" % offset)
	expect(IsoMathScript.world_to_tile(Vector2(-10000, -10000), MapDataScript.MAP_SIZE) == Vector2i(-1, -1), "Out-of-map selection should be invalid")
	for tile in [Vector2i(0, 0), Vector2i(127, 0), Vector2i(0, 127), Vector2i(127, 127)]:
		expect(IsoMathScript.world_to_tile(IsoMathScript.tile_to_world(tile), MapDataScript.MAP_SIZE) == tile, "Boundary tile selection failed for %s" % tile)

func validate_map_generation() -> void:
	var first = MapDataScript.new()
	var second = MapDataScript.new()
	var changed_seed = MapDataScript.new(MapDataScript.MAP_SIZE, MapDataScript.SEED + 1)
	expect(first.terrain.size() == 128 * 128, "Map must contain exactly 128 by 128 tiles")
	expect(first.world_checksum() == second.world_checksum(), "Same seed generated different world data")
	expect(first.terrain_checksum() != changed_seed.terrain_checksum(), "Different seed generated the same terrain")
	expect(first.world_checksum() != changed_seed.world_checksum(), "Different seed generated the same world features")

func validate_world_features() -> void:
	var data = MapDataScript.new()
	for terrain_type in [MapDataScript.Terrain.PLAINS, MapDataScript.Terrain.FOREST, MapDataScript.Terrain.HILL, MapDataScript.Terrain.RIVER, MapDataScript.Terrain.COAST]:
		expect(count_terrain(data, terrain_type) > 0, "Required terrain category is absent: %s" % terrain_type)
	var bridge_count := 0
	var deposit_count := 0
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x, y)
			if data.is_bridge(tile):
				bridge_count += 1
				expect(data.is_river(tile), "Bridge must be located on the river")
				expect(data.is_traversable_ground(tile), "Bridge must make its river tile traversable")
			if data.has_resource_deposit(tile):
				deposit_count += 1
				expect(data.is_land(tile), "Resource deposits must remain land data")
				expect(data.get_resource_deposit(tile) != MapDataScript.ResourceDeposit.NONE, "Deposit query returned NONE")
	expect(bridge_count >= 3, "Prototype map must have deterministic bridge locations")
	expect(deposit_count >= 6, "Prototype map must have several deterministic deposits")

func validate_river_continuity() -> void:
	var data = MapDataScript.new()
	var river_start := Vector2i(-1, -1)
	var river_count := 0
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x, y)
			if data.is_river(tile):
				river_count += 1
				if river_start.x < 0:
					river_start = tile
	expect(river_count > data.size.x / 2, "River is too short to cross the prototype region")
	var visited := PackedByteArray()
	visited.resize(data.size.x * data.size.y)
	var queue: Array[Vector2i] = [river_start]
	visited[data.index(river_start)] = 1
	var cursor := 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction in MapDataScript.CARDINAL_DIRECTIONS:
			var next: Vector2i = current + direction
			if data.is_river(next) and visited[data.index(next)] == 0:
				visited[data.index(next)] = 1
				queue.append(next)
	expect(queue.size() == river_count, "River contains disconnected fragments")

func validate_capitals_and_queries() -> void:
	var data = MapDataScript.new()
	expect(data.is_valid(data.player_capital) and data.is_valid(data.ai_capital), "Capital locations must be in bounds")
	expect(data.is_land(data.player_capital) and data.is_land(data.ai_capital), "Capital locations must be valid land")
	expect(data.player_capital.distance_squared_to(data.ai_capital) >= 64 * 64, "Capitals are not sufficiently separated")
	expect(data.are_ground_tiles_connected(data.player_capital, data.ai_capital), "Capital locations must be mutually reachable")
	expect(not data.is_land(Vector2i(-1, -1)) and not data.is_traversable_ground(Vector2i(-1, -1)), "Out-of-bounds terrain queries must be safe")
	var coast_tile := find_first_terrain(data, MapDataScript.Terrain.COAST)
	expect(data.is_water(coast_tile) and not data.is_land(coast_tile), "Coast land/water queries are inconsistent")

func validate_marker_placement() -> void:
	var data = MapDataScript.new()
	var ground := find_placeable_ground(data)
	var coast := find_first_terrain(data, MapDataScript.Terrain.COAST)
	var river := find_first_terrain(data, MapDataScript.Terrain.RIVER)
	expect(data.can_place_marker(ground), "Valid ground should allow a generic marker")
	expect(data.place_marker(ground), "Valid ground marker placement failed")
	expect(data.has_marker(ground), "Placed marker must be queryable from map data")
	expect(data.marker_count() == 1, "Marker layer should contain one placement")
	expect(not data.can_place_marker(ground) and not data.place_marker(ground), "Duplicate placement must be rejected safely")
	expect(data.marker_count() == 1, "Duplicate placement must not corrupt marker state")
	expect(data.remove_marker(ground), "Marker removal failed")
	expect(not data.has_marker(ground) and data.marker_count() == 0, "Removed marker must clear data state")
	expect(not data.can_place_marker(coast) and not data.place_marker(coast), "Coast placement must be rejected")
	expect(not data.can_place_marker(river) and not data.place_marker(river), "River placement must be rejected")
	expect(not data.place_marker(Vector2i(-1, -1)), "Out-of-bounds placement must be rejected")
	var same_seed = MapDataScript.new()
	expect(same_seed.marker_count() == 0, "New same-seed world must start with a clean marker layer")
	var changed_seed = MapDataScript.new(MapDataScript.MAP_SIZE, MapDataScript.SEED + 1)
	expect(changed_seed.marker_count() == 0, "New different-seed world must start with a clean marker layer")

func count_terrain(data, terrain_type: int) -> int:
	var count := 0
	for value in data.terrain:
		if value == terrain_type:
			count += 1
	return count

func find_first_terrain(data, terrain_type: int) -> Vector2i:
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x, y)
			if data.get_terrain(tile) == terrain_type:
				return tile
	return Vector2i(-1, -1)

func validate_city_simulation() -> void:
	var data = MapDataScript.new()
	var city = CitySimulationScript.new(data)
	var layout := find_city_layout(data)
	var road: Vector2i = layout.road
	var isolated := find_placeable_ground(data)
	expect(city.place_zone(isolated, CitySimulationScript.Zone.RESIDENTIAL), "Unconnected residential zoning failed")
	expect(city.shortage_reason(isolated) == "No road access", "Zone without a road must explain its shortage")
	expect(city.bulldoze(isolated), "Bulldoze must remove an undeveloped zone")
	expect(city.place_road(road), "Valid road placement failed")
	expect(city.place_road(layout.road_two), "Connected road placement failed")
	expect(city.has_road(road) and city.has_road_access(layout.residential), "Road access query failed")
	expect(not city.place_road(find_first_terrain(data, MapDataScript.Terrain.COAST)), "Coast road placement must be rejected")
	var bridge := find_first_bridge(data)
	expect(city.place_road(bridge), "Road placement on a deterministic bridge must succeed")
	expect(city.place_zone(layout.residential, CitySimulationScript.Zone.RESIDENTIAL), "Residential zoning failed")
	expect(city.place_zone(layout.commercial, CitySimulationScript.Zone.COMMERCIAL), "Commercial zoning failed")
	expect(city.shortage_reason(layout.residential) == "No power", "Unserviced zone must explain missing power")
	expect(city.place_utility(layout.power, CitySimulationScript.Building.POWER_PLANT), "Power plant placement failed")
	expect(city.place_utility(layout.water, CitySimulationScript.Building.WATER_FACILITY), "Water facility placement failed")
	expect(city.place_utility(layout.fire, CitySimulationScript.Building.FIRE_STATION), "Fire station placement failed")
	city.tick()
	expect(city.has_power(layout.residential) and city.has_water(layout.residential) and city.has_fire_coverage(layout.residential), "Road-connected utilities did not cover the zone")
	expect(city.get_building(layout.residential) == CitySimulationScript.Building.RESIDENTIAL, "Eligible residential zone did not develop")
	city.tick()
	expect(city.get_building(layout.commercial) == CitySimulationScript.Building.COMMERCIAL, "Eligible commercial zone did not develop")
	for tick in 4:
		city.tick()
	expect(city.household_capacity > 0 and city.occupied_households > 0, "Residential growth did not create occupied households")
	expect(city.job_capacity > 0 and city.employed_workforce <= city.job_capacity and city.employed_workforce <= city.occupied_households, "Employment totals are invalid")
	for resource in city.resources:
		expect(is_finite(resource) and resource >= 0.0, "Resource ledger contains an invalid value")
	expect(city.resources.size() == 7, "All seven prototype resource fields must exist")
	expect(city.get_resource(CitySimulationScript.LedgerResource.MONEY) > 0.0, "Tax/resource tick did not retain valid money")
	expect(city.bulldoze(layout.commercial) and city.get_zone(layout.commercial) == CitySimulationScript.Zone.COMMERCIAL, "Bulldoze must remove a developed building while retaining its zone")

func validate_city_feedback() -> void:
	var data = MapDataScript.new()
	var city = CitySimulationScript.new(data)
	var layout := find_city_layout(data)
	var coast := find_first_terrain(data, MapDataScript.Terrain.COAST)
	expect(not city.place_road(coast) and city.last_action_reason == "Cannot build: Invalid terrain", "Invalid terrain rejection should explain the failure")
	expect(city.place_road(layout.road), "Feedback test road setup failed")
	expect(not city.place_road(layout.road) and city.last_action_reason == "Cannot build: Occupied tile", "Duplicate road rejection should explain the occupied tile")
	var utility_cost: float = city.utility_cost(CitySimulationScript.Building.POWER_PLANT)
	city.resources[CitySimulationScript.LedgerResource.MONEY] = utility_cost - 1.0
	var money_before: float = city.get_resource(CitySimulationScript.LedgerResource.MONEY)
	expect(not city.place_utility(layout.power, CitySimulationScript.Building.POWER_PLANT), "Insufficient-money utility placement should fail")
	expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MONEY), money_before), "Failed construction must not deduct money")
	expect(city.last_action_reason == "Cannot build: Not enough money", "Insufficient-money failure reason is incorrect")
	city.resources[CitySimulationScript.LedgerResource.MONEY] = utility_cost + 10.0
	var money_for_success: float = city.get_resource(CitySimulationScript.LedgerResource.MONEY)
	expect(city.place_utility(layout.power, CitySimulationScript.Building.POWER_PLANT), "Sufficient-money utility placement should succeed")
	expect(is_equal_approx(city.get_resource(CitySimulationScript.LedgerResource.MONEY), money_for_success - utility_cost), "Successful construction deducted the wrong cost")
	expect(city.last_action_reason == "Power plant placed", "Successful construction feedback is incorrect")
	var disconnected_data = MapDataScript.new()
	var disconnected_city = CitySimulationScript.new(disconnected_data)
	var disconnected_tile := find_placeable_ground(disconnected_data)
	expect(disconnected_city.place_zone(disconnected_tile, CitySimulationScript.Zone.RESIDENTIAL), "Disconnected-zone feedback setup failed")
	var disconnected_summary := disconnected_city.selection_summary(disconnected_tile)
	expect(disconnected_summary.contains("Road: No access"), "Disconnected zone should report missing road access")
	expect(disconnected_summary.contains("Power: No power"), "Disconnected zone should report missing power")
	expect(disconnected_summary.contains("Water: No water"), "Disconnected zone should report missing water")
	expect(disconnected_summary.contains("Fire: Not covered"), "Disconnected zone should report missing fire coverage")
	var serviced_data = MapDataScript.new()
	var serviced_city = CitySimulationScript.new(serviced_data)
	var serviced_layout := find_city_layout(serviced_data)
	expect(serviced_city.place_road(serviced_layout.road), "Serviced feedback road setup failed")
	expect(serviced_city.place_road(serviced_layout.road_two), "Serviced feedback road extension failed")
	expect(serviced_city.place_zone(serviced_layout.residential, CitySimulationScript.Zone.RESIDENTIAL), "Serviced feedback residential setup failed")
	expect(serviced_city.place_zone(serviced_layout.commercial, CitySimulationScript.Zone.COMMERCIAL), "Serviced feedback commercial setup failed")
	expect(serviced_city.place_utility(serviced_layout.power, CitySimulationScript.Building.POWER_PLANT), "Serviced feedback power setup failed")
	expect(serviced_city.place_utility(serviced_layout.water, CitySimulationScript.Building.WATER_FACILITY), "Serviced feedback water setup failed")
	expect(serviced_city.place_utility(serviced_layout.fire, CitySimulationScript.Building.FIRE_STATION), "Serviced feedback fire setup failed")
	serviced_city.tick()
	var serviced_summary := serviced_city.selection_summary(serviced_layout.residential)
	expect(serviced_summary.contains("Road: Connected"), "Serviced zone should report road connectivity")
	expect(serviced_summary.contains("Power: Connected"), "Serviced zone should report power connectivity")
	expect(serviced_summary.contains("Water: Connected"), "Serviced zone should report water connectivity")
	expect(serviced_summary.contains("Fire: Covered"), "Serviced zone should report fire coverage")
	expect(serviced_summary.contains("Households:"), "Residential selection should report household capacity")
	serviced_city.tick()
	var commercial_summary := serviced_city.selection_summary(serviced_layout.commercial)
	expect(commercial_summary.contains("Road: Connected"), "Commercial selection should report road connectivity")
	expect(commercial_summary.contains("Power: Connected"), "Commercial selection should report power connectivity")
	expect(commercial_summary.contains("Water: Connected"), "Commercial selection should report water connectivity")
	expect(commercial_summary.contains("Fire: Covered"), "Commercial selection should report fire coverage")
	expect(commercial_summary.contains("Jobs:"), "Commercial selection should report job capacity")

func validate_visual_assets() -> void:
	# Imported source-art assets must resolve before the cached rendering paths use
	# them. These checks also lock visual mappings to every simulation type.
	expect(load("res://assets/buildings/isometric_buildings_atlas_v1.png") != null, "Building atlas failed to import")
	expect(load("res://assets/terrain/isometric_terrain_atlas_v1.png") != null, "Terrain atlas failed to import")
	expect(load("res://assets/units/isometric_units_atlas_v1.png") != null, "Unit atlas failed to import")
	var data = MapDataScript.new()
	var city = CitySimulationScript.new(data)
	var buildings = BuildingOverlayScript.new()
	buildings.configure(data, city, Vector2i.ZERO)
	for building_type in range(CitySimulationScript.Building.POWER_PLANT, CitySimulationScript.Building.MISSILE_SILO + 1):
		expect(buildings.BUILDING_CELLS.has(building_type), "Prototype building type lacks an atlas region: %s" % building_type)
	var sample := Vector2i(19, 23)
	expect(buildings.deterministic_variant(sample) == buildings.deterministic_variant(sample), "Building variants must be deterministic")
	var terrain = TerrainDetailOverlayScript.new()
	terrain.configure(data, Vector2i.ZERO, city)
	for terrain_type in [MapDataScript.Terrain.PLAINS, MapDataScript.Terrain.FOREST, MapDataScript.Terrain.HILL, MapDataScript.Terrain.RIVER, MapDataScript.Terrain.COAST]:
		expect(terrain.TERRAIN_CELLS.has(terrain_type), "Terrain type lacks an atlas region: %s" % terrain_type)
	for unit_type in range(CitySimulationScript.UnitType.INFANTRY, CitySimulationScript.UnitType.FIGHTER + 1):
		expect(CombatRendererScript.UNIT_CELLS.has(unit_type), "Unit type lacks an atlas region: %s" % unit_type)
	buildings.free()
	terrain.free()

func find_first_bridge(data) -> Vector2i:
	for y in data.size.y:
		for x in data.size.x:
			var tile := Vector2i(x, y)
			if data.is_bridge(tile):
				return tile
	return Vector2i(-1, -1)

func find_city_layout(data) -> Dictionary:
	for y in range(2, data.size.y - 2):
		for x in range(2, data.size.x - 3):
			var road := Vector2i(x, y)
			var tiles := [road, road + Vector2i(1, 0), road + Vector2i(0, 1), road + Vector2i(1, 1), road + Vector2i(-1, 0), road + Vector2i(0, -1), road + Vector2i(1, -1)]
			var valid := true
			for tile in tiles:
				if not data.is_land(tile):
					valid = false
			if valid:
				return {"road": road, "road_two": road + Vector2i(1, 0), "residential": road + Vector2i(0, 1), "commercial": road + Vector2i(1, 1), "power": road + Vector2i(-1, 0), "water": road + Vector2i(0, -1), "fire": road + Vector2i(1, -1)}
	return {}

func validate_chunks_and_culling() -> void:
	var data = MapDataScript.new()
	var city = CitySimulationScript.new(data)
	var world = WorldRendererScript.new()
	get_root().add_child(world)
	world.configure(data, city)
	expect(world.chunks.size() == 64, "A 128 by 128 map must create 64 sixteen-tile chunks")
	var rendered_capacity := 0
	var chunk_coordinates := {}
	for chunk in world.chunks:
		expect(chunk.map_data == data, "Chunk must reference map data rather than own simulation state")
		expect(chunk.tile_count() == ChunkRendererScript.CHUNK_SIZE * ChunkRendererScript.CHUNK_SIZE, "Full-size chunk has incorrect tile ownership")
		expect(chunk.world_bounds().size.x > 0.0 and chunk.world_bounds().size.y > 0.0, "Chunk bounds must be non-empty")
		expect(chunk.mesh_instance.mesh != null, "Chunk must build a cached terrain mesh")
		expect(chunk.terrain_details != null and chunk.terrain_details.map_data == data, "Each chunk must initialize its cached terrain-detail overlay")
		expect(chunk.building_overlay != null and chunk.ai_building_overlay != null, "Each chunk must initialize cached building overlays")
		expect(chunk.visual_rebuild_count == 1, "Static terrain should build exactly once during configuration")
		rendered_capacity += chunk.tile_count()
		chunk_coordinates[chunk.chunk] = true
	expect(rendered_capacity == 128 * 128, "Chunks must own every map tile exactly once")
	expect(chunk_coordinates.size() == 64, "Chunk coordinates must be unique")
	var camera := Camera2D.new()
	get_root().add_child(camera)
	camera.position = IsoMathScript.tile_to_world(Vector2i(64, 64))
	camera.zoom = Vector2(0.75, 0.75)
	world.update_visibility(camera)
	expect(world.visible_chunks > 0 and world.visible_chunks <= world.chunks.size(), "Chunk culling must expose a non-zero bounded set")
	expect(world.rendered_tiles > 0 and world.rendered_tiles <= 128 * 128, "Culling must report a bounded rendered tile count")
	var first_visibility_update_count: int = world.visibility_update_count
	world.update_visibility(camera)
	expect(world.visibility_update_count == first_visibility_update_count, "Unchanged camera must not repeat chunk culling")
	camera.position += Vector2(64, 0)
	world.update_visibility(camera)
	expect(world.visibility_update_count == first_visibility_update_count + 1, "Moved camera must update chunk culling")
	for chunk in world.chunks:
		expect(chunk.visual_rebuild_count == 1, "Camera visibility changes must not rebuild static terrain")
	var marker_tile := find_first_terrain(data, MapDataScript.Terrain.PLAINS)
	marker_tile = find_placeable_ground(data)
	var rebuild_counts := {}
	var feature_counts := {}
	for chunk in world.chunks:
		rebuild_counts[chunk.chunk] = chunk.visual_rebuild_count
		feature_counts[chunk.chunk] = chunk.visible_feature_count
	expect(data.place_marker(marker_tile), "Localized marker placement setup failed")
	world.refresh_tile(marker_tile)
	var marker_chunk := Vector2i(floori(float(marker_tile.x) / ChunkRendererScript.CHUNK_SIZE), floori(float(marker_tile.y) / ChunkRendererScript.CHUNK_SIZE))
	expect(world.chunks[marker_chunk.y * 8 + marker_chunk.x].visible_feature_count == feature_counts[marker_chunk] + 1, "Affected chunk mesh must include the new marker geometry")
	expect(data.has_marker(marker_tile), "Marker must remain in tile data after placement")
	camera.position += Vector2(96, 48)
	camera.zoom = Vector2(1.4, 1.4)
	world.update_visibility(camera)
	expect(data.has_marker(marker_tile), "Camera movement and zoom must not alter tile marker state")
	for chunk in world.chunks:
		if chunk.chunk == marker_chunk:
			expect(chunk.visual_rebuild_count == rebuild_counts[chunk.chunk] + 1, "Placed marker must refresh its affected chunk")
		else:
			expect(chunk.visual_rebuild_count == rebuild_counts[chunk.chunk], "Placed marker must not rebuild unrelated chunks")
	var city_tile := find_placeable_ground_except(data, marker_tile)
	var city_rebuild_counts := {}
	var city_feature_counts := {}
	for chunk in world.chunks:
		city_rebuild_counts[chunk.chunk] = chunk.visual_rebuild_count
		city_feature_counts[chunk.chunk] = chunk.visible_feature_count
	expect(city.place_road(city_tile), "City road setup for localized rendering test failed")
	world.refresh_tile(city_tile)
	var city_chunk := Vector2i(floori(float(city_tile.x) / ChunkRendererScript.CHUNK_SIZE), floori(float(city_tile.y) / ChunkRendererScript.CHUNK_SIZE))
	expect(world.chunks[city_chunk.y * 8 + city_chunk.x].visible_feature_count == city_feature_counts[city_chunk] + 1, "City road geometry must appear in its affected chunk")
	for chunk in world.chunks:
		if chunk.chunk == city_chunk:
			expect(chunk.visual_rebuild_count == city_rebuild_counts[chunk.chunk] + 1, "City placement must refresh its affected chunk")
		else:
			expect(chunk.visual_rebuild_count == city_rebuild_counts[chunk.chunk], "City placement must not rebuild unrelated chunks")
	camera.queue_free()
	world.queue_free()

func validate_main_scene_initialization() -> void:
	var main = MainScene.instantiate()
	get_root().add_child(main)
	expect(main.map_data.size == Vector2i(128, 128), "Main scene did not initialize the 128 by 128 map")
	expect(main.world_renderer.chunks.size() == 64, "Main scene did not create its chunk renderers")
	expect(main.overlay.label.get_parent() == main.overlay, "Debug overlay label did not initialize")
	expect(main.camera.zoom.x >= 0.35 and main.camera.zoom.x <= 2.25, "Camera zoom initialized outside intended range")
	var initial_target_zoom: float = main.target_zoom
	var zoom_in_key := InputEventKey.new()
	zoom_in_key.pressed = true
	zoom_in_key.keycode = KEY_EQUAL
	main._unhandled_input(zoom_in_key)
	expect(main.target_zoom > initial_target_zoom, "Keyboard and wheel zoom helper must zoom in")
	main.change_zoom(0.0001)
	expect(main.target_zoom == main.MIN_ZOOM, "Zoom helper must clamp to the minimum zoom")
	var placement_tile := find_placeable_ground(main.map_data)
	main.selected_tile = placement_tile
	var place_key := InputEventKey.new()
	place_key.pressed = true
	place_key.keycode = KEY_P
	get_root().get_viewport().push_input(place_key)
	expect(main.map_data.has_marker(placement_tile), "P key must place a marker on the selected ground tile")
	var remove_key := InputEventKey.new()
	remove_key.pressed = true
	remove_key.keycode = KEY_DELETE
	get_root().get_viewport().push_input(remove_key)
	expect(not main.map_data.has_marker(placement_tile), "Delete key must remove the selected marker")
	expect(main.map_data.place_marker(placement_tile), "Marker should be placeable again after Delete")
	var backspace_key := InputEventKey.new()
	backspace_key.pressed = true
	backspace_key.keycode = KEY_BACKSPACE
	get_root().get_viewport().push_input(backspace_key)
	expect(not main.map_data.has_marker(placement_tile), "Backspace key must remove the selected marker")
	main.city.resources[CitySimulationScript.LedgerResource.MONEY] = 0.0
	var utility_key := InputEventKey.new()
	utility_key.pressed = true
	utility_key.keycode = KEY_3
	main._unhandled_input(utility_key)
	expect(main.city.last_action_reason == "Cannot build: Not enough money", "Main input path should expose insufficient-money feedback")
	main.update_debug_overlay(0.016)
	expect(main.overlay.label.text.contains("Cannot build: Not enough money"), "Overlay should display construction failure feedback")
	var default_world_checksum: int = main.map_data.world_checksum()
	main.regenerate_world(MapDataScript.SEED + 1)
	expect(main.map_data.world_checksum() != default_world_checksum, "Developer regeneration must apply a specified seed")
	main.regenerate_world(MapDataScript.SEED)
	expect(main.map_data.world_checksum() == default_world_checksum, "Developer regeneration must reproduce a prior seed")
	main.queue_free()

func find_placeable_ground(data) -> Vector2i:
	for terrain_type in [MapDataScript.Terrain.PLAINS, MapDataScript.Terrain.FOREST, MapDataScript.Terrain.HILL]:
		for y in data.size.y:
			for x in data.size.x:
				var tile := Vector2i(x, y)
				if data.get_terrain(tile) == terrain_type and data.is_traversable_ground(tile) and not data.has_resource_deposit(tile) and not data.is_capital_marker(tile):
					return tile
	return Vector2i(-1, -1)

func find_placeable_ground_except(data, excluded: Vector2i) -> Vector2i:
	for terrain_type in [MapDataScript.Terrain.PLAINS, MapDataScript.Terrain.FOREST, MapDataScript.Terrain.HILL]:
		for y in data.size.y:
			for x in data.size.x:
				var tile := Vector2i(x, y)
				if tile != excluded and data.get_terrain(tile) == terrain_type and data.is_traversable_ground(tile) and not data.has_resource_deposit(tile) and not data.is_capital_marker(tile):
					return tile
	return Vector2i(-1, -1)
