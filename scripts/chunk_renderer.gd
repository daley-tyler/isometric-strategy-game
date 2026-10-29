class_name ChunkRenderer
extends Node2D

const CHUNK_SIZE := 16
const MapDataScript = preload("res://scripts/map_data.gd")
const IsoMathScript = preload("res://scripts/iso_math.gd")
const BuildingOverlayScript = preload("res://scripts/building_overlay.gd")
const TerrainDetailOverlayScript = preload("res://scripts/terrain_detail_overlay.gd")

var map_data
var city_data
var ai_city_data
var chunk: Vector2i
var mesh_instance: MeshInstance2D
var building_overlay: Node2D
var ai_building_overlay: Node2D
var terrain_details: Node2D
var cached_bounds := Rect2()
var owned_tile_count := 0
var visual_rebuild_count := 0
var visible_feature_count := 0

func _init() -> void:
	mesh_instance = MeshInstance2D.new()
	add_child(mesh_instance)
	terrain_details = TerrainDetailOverlayScript.new()
	terrain_details.z_index = 1
	add_child(terrain_details)
	building_overlay = BuildingOverlayScript.new()
	building_overlay.z_index = 100
	add_child(building_overlay)
	ai_building_overlay = BuildingOverlayScript.new()
	ai_building_overlay.z_index = 100
	add_child(ai_building_overlay)

func configure(data: MapData, chunk_coordinate: Vector2i, city = null, ai_city = null) -> void:
	map_data = data
	city_data = city
	ai_city_data = ai_city
	chunk = chunk_coordinate
	cache_metadata()
	terrain_details.configure(map_data, chunk, city_data, ai_city_data)
	# Each cached sprite render item has absolute tile-foot-point depth, so
	# overlapping sprites interleave correctly even across chunk/owner boundaries.
	building_overlay.z_index = 0
	ai_building_overlay.z_index = 0
	building_overlay.configure(map_data, city_data, chunk)
	ai_building_overlay.configure(map_data, ai_city_data, chunk, Color("d96b78"))
	rebuild_visual()

func tile_count() -> int:
	return owned_tile_count

func world_bounds() -> Rect2:
	return cached_bounds

func cache_metadata() -> void:
	var start := chunk * CHUNK_SIZE
	var end := Vector2i(mini(start.x + CHUNK_SIZE - 1, map_data.size.x - 1), mini(start.y + CHUNK_SIZE - 1, map_data.size.y - 1))
	owned_tile_count = (end.x - start.x + 1) * (end.y - start.y + 1)
	var top_left := IsoMathScript.tile_to_world(start)
	var top_right := IsoMathScript.tile_to_world(Vector2i(end.x, start.y))
	var bottom_left := IsoMathScript.tile_to_world(Vector2i(start.x, end.y))
	var bottom_right := IsoMathScript.tile_to_world(end)
	var minimum := Vector2(minf(minf(top_left.x, top_right.x), minf(bottom_left.x, bottom_right.x)), minf(minf(top_left.y, top_right.y), minf(bottom_left.y, bottom_right.y)))
	var maximum := Vector2(maxf(maxf(top_left.x, top_right.x), maxf(bottom_left.x, bottom_right.x)), maxf(maxf(top_left.y, top_right.y), maxf(bottom_left.y, bottom_right.y)))
	cached_bounds = Rect2(minimum - Vector2(IsoMathScript.HALF_WIDTH, IsoMathScript.HALF_HEIGHT), maximum - minimum + Vector2(IsoMathScript.TILE_WIDTH, IsoMathScript.TILE_HEIGHT))

func rebuild_visual() -> void:
	if map_data == null:
		return
	var start := chunk * CHUNK_SIZE
	var finish := Vector2i(mini(start.x + CHUNK_SIZE, map_data.size.x), mini(start.y + CHUNK_SIZE, map_data.size.y))
	var feature_count := feature_count_in_range(start, finish)
	visible_feature_count = feature_count
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize((owned_tile_count + feature_count) * 4)
	colors.resize((owned_tile_count + feature_count) * 4)
	indices.resize((owned_tile_count + feature_count) * 6)
	var tile_number := 0
	for y in range(start.y, finish.y):
		for x in range(start.x, finish.x):
			var center := IsoMathScript.tile_to_world(Vector2i(x, y))
			var vertex_index := tile_number * 4
			var index_index := tile_number * 6
			vertices[vertex_index] = center + Vector2(0, -IsoMathScript.HALF_HEIGHT)
			vertices[vertex_index + 1] = center + Vector2(IsoMathScript.HALF_WIDTH, 0)
			vertices[vertex_index + 2] = center + Vector2(0, IsoMathScript.HALF_HEIGHT)
			vertices[vertex_index + 3] = center + Vector2(-IsoMathScript.HALF_WIDTH, 0)
			var tile := Vector2i(x, y)
			var color := terrain_color(map_data.get_terrain(tile))
			if map_data.has_scorch(tile): color = color.darkened(0.62)
			colors[vertex_index] = color
			colors[vertex_index + 1] = color
			colors[vertex_index + 2] = color
			colors[vertex_index + 3] = color
			indices[index_index] = vertex_index
			indices[index_index + 1] = vertex_index + 1
			indices[index_index + 2] = vertex_index + 2
			indices[index_index + 3] = vertex_index
			indices[index_index + 4] = vertex_index + 2
			indices[index_index + 5] = vertex_index + 3
			tile_number += 1
	var feature_number := tile_number
	for y in range(start.y, finish.y):
		for x in range(start.x, finish.x):
			var tile := Vector2i(x, y)
			if not has_visible_feature(tile):
				continue
			write_diamond(vertices, colors, indices, feature_number, IsoMathScript.tile_to_world(tile), feature_half_extents(tile), feature_color(tile))
			feature_number += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var terrain_mesh := ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = terrain_mesh
	building_overlay.refresh()
	ai_building_overlay.refresh()
	terrain_details.refresh()
	visual_rebuild_count += 1

func feature_count_in_range(start: Vector2i, finish: Vector2i) -> int:
	var count := 0
	for y in range(start.y, finish.y):
		for x in range(start.x, finish.x):
			if has_visible_feature(Vector2i(x, y)):
				count += 1
	return count

func has_visible_feature(tile: Vector2i) -> bool:
	return map_data.is_bridge(tile) or map_data.has_resource_deposit(tile) or map_data.is_capital_marker(tile) or map_data.has_marker(tile) or city_feature_at(city_data, tile) or city_feature_at(ai_city_data, tile)

func city_feature_at(city, tile: Vector2i) -> bool:
	return city != null and (city.has_rubble(tile) or city.has_road(tile) or city.get_zone(tile) != 0 or city.get_building(tile) != 0)

func write_diamond(vertices: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, element_number: int, center: Vector2, half_extents: Vector2, color: Color) -> void:
	var vertex_index := element_number * 4
	var index_index := element_number * 6
	vertices[vertex_index] = center + Vector2(0, -half_extents.y)
	vertices[vertex_index + 1] = center + Vector2(half_extents.x, 0)
	vertices[vertex_index + 2] = center + Vector2(0, half_extents.y)
	vertices[vertex_index + 3] = center + Vector2(-half_extents.x, 0)
	colors[vertex_index] = color
	colors[vertex_index + 1] = color
	colors[vertex_index + 2] = color
	colors[vertex_index + 3] = color
	indices[index_index] = vertex_index
	indices[index_index + 1] = vertex_index + 1
	indices[index_index + 2] = vertex_index + 2
	indices[index_index + 3] = vertex_index
	indices[index_index + 4] = vertex_index + 2
	indices[index_index + 5] = vertex_index + 3

func feature_half_extents(tile: Vector2i) -> Vector2:
	var city = city_data if city_feature_at(city_data, tile) else ai_city_data
	if city != null and city.has_rubble(tile):
		return Vector2(IsoMathScript.HALF_WIDTH * 0.45, IsoMathScript.HALF_HEIGHT * 0.24)
	if city != null and city.get_building(tile) != 0:
		return Vector2(IsoMathScript.HALF_WIDTH * 0.52, IsoMathScript.HALF_HEIGHT * 0.52)
	if city != null and city.get_zone(tile) != 0:
		return Vector2(IsoMathScript.HALF_WIDTH * 0.72, IsoMathScript.HALF_HEIGHT * 0.32)
	if city != null and city.has_road(tile):
		return Vector2(IsoMathScript.HALF_WIDTH * 0.78, IsoMathScript.HALF_HEIGHT * 0.16)
	if map_data.has_marker(tile):
		return Vector2(IsoMathScript.HALF_WIDTH * 0.36, IsoMathScript.HALF_HEIGHT * 0.36)
	if map_data.is_bridge(tile):
		return Vector2(IsoMathScript.HALF_WIDTH * 0.72, IsoMathScript.HALF_HEIGHT * 0.28)
	if map_data.is_capital_marker(tile):
		return Vector2(IsoMathScript.HALF_WIDTH * 0.46, IsoMathScript.HALF_HEIGHT * 0.46)
	return Vector2(IsoMathScript.HALF_WIDTH * 0.25, IsoMathScript.HALF_HEIGHT * 0.25)

func feature_color(tile: Vector2i) -> Color:
	var city = city_data if city_feature_at(city_data, tile) else ai_city_data
	if city != null:
		if city.has_rubble(tile): return Color("413b39")
		match city.get_building(tile):
			1: return Color("e8c75a")
			2: return Color("5fa9d7")
			3: return Color("df654f")
			4: return Color("98d878")
			5: return Color("b98adf")
			6: return Color("d4aa5b")
			7: return Color("9c9c9c")
			8: return Color("c7774c")
			9: return Color("6aa7ba")
			10: return Color("a75f69")
			11: return Color("d2b7e5")
			12: return Color("aa8ac8")
			13: return Color("718a5d")
			14: return Color("7e7f91")
			15: return Color("6c93a8")
			16: return Color("8ba9d0")
			17: return Color("c5a75b")
			18: return Color("9e5b5b")
		if city.get_zone(tile) == 1: return Color("7fbf72")
		if city.get_zone(tile) == 2: return Color("76aee0")
		if city.has_road(tile): return Color("6e6d69")
	if map_data.has_marker(tile):
		return Color("f4dc75")
	if tile == map_data.player_capital:
		return Color("f0d65a")
	if tile == map_data.ai_capital:
		return Color("db6a87")
	if map_data.is_bridge(tile):
		return Color("c99b62")
	match map_data.get_resource_deposit(tile):
		MapDataScript.ResourceDeposit.IRON: return Color("a4a9b0")
		MapDataScript.ResourceDeposit.STONE: return Color("d2d0bd")
		_: return Color("292c38")

func terrain_color(terrain: int) -> Color:
	match terrain:
		MapDataScript.Terrain.RIVER: return Color("4d9fbd")
		MapDataScript.Terrain.COAST: return Color("4a8cae")
		MapDataScript.Terrain.FOREST: return Color("4c8758")
		MapDataScript.Terrain.HILL: return Color("a99a62")
		_: return Color("7dbc68")
