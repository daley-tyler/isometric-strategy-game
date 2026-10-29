class_name WorldRenderer
extends Node2D

const ChunkRendererScript = preload("res://scripts/chunk_renderer.gd")
const IsoMathScript = preload("res://scripts/iso_math.gd")

var map_data
var city_data
var ai_city_data
var chunks: Array = []
var visible_chunks := 0
var rendered_tiles := 0
var visibility_update_count := 0
var last_camera_position := Vector2(INF, INF)
var last_viewport_size := Vector2.ZERO

func configure(data: MapData, city = null, ai_city = null) -> void:
	clear_chunks()
	map_data = data
	city_data = city
	ai_city_data = ai_city
	var chunks_x := ceili(float(data.size.x) / ChunkRendererScript.CHUNK_SIZE)
	var chunks_y := ceili(float(data.size.y) / ChunkRendererScript.CHUNK_SIZE)
	for y in chunks_y:
		for x in chunks_x:
			var renderer := ChunkRendererScript.new()
			add_child(renderer)
			renderer.configure(data, Vector2i(x, y), city_data, ai_city_data)
			chunks.append(renderer)
	last_camera_position = Vector2(INF, INF)
	last_viewport_size = Vector2.ZERO

func clear_chunks() -> void:
	for chunk in chunks:
		remove_child(chunk)
		chunk.queue_free()
	chunks.clear()

func refresh_tile(tile: Vector2i) -> void:
	refresh_tiles([tile])

func refresh_tiles(tiles: Array[Vector2i]) -> void:
	if map_data == null:
		return
	var chunks_x := ceili(float(map_data.size.x) / ChunkRendererScript.CHUNK_SIZE)
	var changed_chunks := {}
	var adjacent_chunks := {}
	for tile in tiles:
		if not map_data.is_valid(tile):
			continue
		var chunk_index := chunk_index_at(tile, chunks_x)
		changed_chunks[chunk_index] = true
		for direction in map_data.CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = tile + direction
			if map_data.is_valid(neighbor):
				adjacent_chunks[chunk_index_at(neighbor, chunks_x)] = true
	# A blast or several developments can change many tiles in the same chunk.
	# Rebuild each affected mesh once after the complete simulation tick.
	for chunk_index in changed_chunks:
		chunks[chunk_index].rebuild_visual()
	for chunk_index in adjacent_chunks:
		if not changed_chunks.has(chunk_index):
			chunks[chunk_index].terrain_details.refresh()

func chunk_index_at(tile: Vector2i, chunks_x: int) -> int:
	return floori(float(tile.y) / ChunkRendererScript.CHUNK_SIZE) * chunks_x + floori(float(tile.x) / ChunkRendererScript.CHUNK_SIZE)

func update_visibility(camera: Camera2D) -> void:
	var viewport_size := get_viewport_rect().size / camera.zoom
	if camera.global_position.is_equal_approx(last_camera_position) and viewport_size.is_equal_approx(last_viewport_size):
		return
	last_camera_position = camera.global_position
	last_viewport_size = viewport_size
	var visible_world := Rect2(camera.global_position - viewport_size * 0.5, viewport_size).grow(maxf(IsoMathScript.TILE_WIDTH, IsoMathScript.TILE_HEIGHT))
	visible_chunks = 0
	rendered_tiles = 0
	for chunk in chunks:
		var should_draw := visible_world.intersects(chunk.world_bounds())
		chunk.visible = should_draw
		if should_draw:
			visible_chunks += 1
			rendered_tiles += chunk.tile_count()
	visibility_update_count += 1
