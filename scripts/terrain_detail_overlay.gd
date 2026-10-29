class_name TerrainDetailOverlay
extends Node2D

const IsoMathScript = preload("res://scripts/iso_math.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const TERRAIN_ATLAS: Texture2D = preload("res://assets/terrain/isometric_terrain_atlas_v1.png")
const TERRAIN_CELLS := {
	MapDataScript.Terrain.PLAINS: Vector2i(0, 0),
	MapDataScript.Terrain.FOREST: Vector2i(1, 0),
	MapDataScript.Terrain.HILL: Vector2i(2, 0),
	MapDataScript.Terrain.RIVER: Vector2i(0, 1),
	MapDataScript.Terrain.COAST: Vector2i(1, 1),
}
const CELL_SIZE := Vector2(512, 512)

var map_data
var city_data
var ai_city_data
var chunk := Vector2i.ZERO

func configure(data, chunk_coordinate: Vector2i, city = null, ai_city = null) -> void:
	map_data = data
	city_data = city
	ai_city_data = ai_city
	chunk = chunk_coordinate
	queue_redraw()

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if map_data == null: return
	var start := chunk * 16
	var finish := Vector2i(mini(start.x + 16, map_data.size.x), mini(start.y + 16, map_data.size.y))
	for y in range(start.y, finish.y):
		for x in range(start.x, finish.x):
			var tile := Vector2i(x, y)
			var center := IsoMathScript.tile_to_world(tile)
			var cell: Vector2i = TERRAIN_CELLS.get(map_data.get_terrain(tile), Vector2i(0, 0))
			if map_data.has_scorch(tile): cell = Vector2i(2, 1)
			# Map only the painted TOP surface to the canonical diamond. Atlas
			# padding and the painted slab walls never enter the terrain mesh.
			if map_data.is_water(tile): cell = Vector2i(0, 1)
			var source_center := Vector2(266 + cell.x * 503, 329 if cell.y == 0 else 694)
			var uv := PackedVector2Array([source_center + Vector2(0, -138), source_center + Vector2(234, 0), source_center + Vector2(0, 136), source_center + Vector2(-236, 0)])
			for point in uv.size(): uv[point] /= TERRAIN_ATLAS.get_size()
			draw_polygon(IsoMathScript.diamond(center), PackedColorArray([Color.WHITE]), uv, TERRAIN_ATLAS)
			var metadata := edge_metadata(map_data, tile)
			var corners := IsoMathScript.diamond(center)
			for edge in metadata.shore_edges:
				draw_line(corners[edge], corners[(edge + 1) % 4], Color("d6c092"), 3.0, true)
				draw_line(corners[edge], corners[(edge + 1) % 4], Color("eef0c9"), 1.0, true)
	# Infrastructure is drawn after ALL surfaces to avoid neighboring art hiding it.
	for y in range(start.y, finish.y):
		for x in range(start.x, finish.x):
			var tile := Vector2i(x, y)
			var center := IsoMathScript.tile_to_world(tile)
			if map_data.is_bridge(tile):
				draw_bridge(center)
			elif has_road(tile):
				draw_road(tile, center)
			else:
				# Keep data markers/zones/rubble visible above the textured surface.
				var owner = get_parent()
				var has_building: bool = (city_data != null and city_data.get_building(tile) != 0) or (ai_city_data != null and ai_city_data.get_building(tile) != 0)
				if owner.has_method("has_visible_feature") and owner.has_visible_feature(tile) and not has_building:
					var extents: Vector2 = owner.feature_half_extents(tile)
					var points := IsoMathScript.diamond()
					for i in points.size(): points[i] = center + points[i] * extents / Vector2(32, 16)
					draw_colored_polygon(points, owner.feature_color(tile))

func has_road(tile: Vector2i) -> bool:
	return (city_data != null and city_data.has_road(tile)) or (ai_city_data != null and ai_city_data.has_road(tile))

static func edge_metadata(data, tile: Vector2i) -> Dictionary:
	var shared: Array[int] = []
	var shore: Array[int] = []
	var exposed: Array[int] = []
	var directions := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for edge in 4:
		var neighbor: Vector2i = tile + directions[edge]
		if not data.is_valid(neighbor): exposed.append(edge)
		elif data.is_water(tile) and data.is_water(neighbor): shared.append(edge)
		elif data.is_water(tile) and data.is_land(neighbor): shore.append(edge)
	return {"shared_edges": shared, "shore_edges": shore, "side_faces": exposed, "bridge": data.is_bridge(tile)}

func draw_road(tile: Vector2i, center: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -10), center + Vector2(18, 0), center + Vector2(0, 10), center + Vector2(-18, 0)]), Color("434a52"))
	for direction in MapDataScript.CARDINAL_DIRECTIONS:
		if has_road(tile + direction) or map_data.is_bridge(tile + direction):
			var edge := IsoMathScript.tile_to_world(tile + direction) - center
			draw_line(center, center + edge * 0.48, Color("343b43"), 8.0, true)
			draw_line(center, center + edge * 0.48, Color("7e8790"), 3.0, true)
	draw_circle(center, 2.2, Color("b8c2c6"))

func draw_bridge(center: Vector2) -> void:
	# Existing bridge generation crosses the river along tile Y (constant X).
	# Endpoints meet neighboring bridge tile endpoints exactly.
	var along := Vector2(-16, 8)
	var across := Vector2(7, 3.5)
	var a := center - along
	var b := center + along
	draw_colored_polygon(PackedVector2Array([a - across, a + across, b + across, b - across]), Color("76533c"))
	for step in 6:
		var plank := a.lerp(b, float(step) / 5.0)
		draw_line(plank - across, plank + across, Color("d4ab70"), 1.5)
	for side in [-1, 1]:
		draw_line(a + across * side, b + across * side, Color("e7c58a"), 2.0)
