class_name CombatRenderer
extends Node2D

const CombatConfigScript = preload("res://scripts/combat_config.gd")
const StrategicConfigScript = preload("res://scripts/strategic_config.gd")
const IsoMathScript = preload("res://scripts/iso_math.gd")
const UNIT_ATLAS: Texture2D = preload("res://assets/units/isometric_units_atlas_v1.png")
const UNIT_CELL_SIZE := Vector2(443.5, 443.5)
const UNIT_CELLS := {
	1: Vector2i(0, 0), 2: Vector2i(1, 0), 3: Vector2i(2, 0), 4: Vector2i(3, 0),
	5: Vector2i(0, 1), 6: Vector2i(2, 1), 7: Vector2i(1, 1),
}

var map_data
var combat_data
var strategic_data
var territory_tiles: Dictionary = {}
var missile_preview_tile := Vector2i(-1, -1)
var missile_preview_active := false
var presentation_items: Array[RID] = []

func _init() -> void:
	z_index = 900

func clear_presentation_items() -> void:
	for item in presentation_items: RenderingServer.free_rid(item)
	presentation_items.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: clear_presentation_items()

func depth_item(depth: int) -> RID:
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, get_canvas_item())
	RenderingServer.canvas_item_set_z_as_relative_to_parent(item, false)
	RenderingServer.canvas_item_set_z_index(item, depth)
	presentation_items.append(item)
	return item

func configure(data, combat, strategic = null) -> void:
	map_data = data
	combat_data = combat
	strategic_data = strategic
	territory_tiles.clear()
	queue_redraw()

func refresh_units() -> void:
	# Unit movement redraws this dedicated overlay only; cached terrain chunks are untouched.
	queue_redraw()

func refresh_territory(changed_tiles: Array[Vector2i]) -> void:
	for tile in changed_tiles:
		if map_data.is_valid(tile): territory_tiles[tile] = combat_data.territory[map_data.index(tile)]
	queue_redraw()

func set_missile_preview(active: bool, tile: Vector2i = Vector2i(-1, -1)) -> void:
	missile_preview_active = active and map_data != null and map_data.is_valid(tile)
	missile_preview_tile = tile if missile_preview_active else Vector2i(-1, -1)
	queue_redraw()

func _draw() -> void:
	clear_presentation_items()
	if map_data == null or combat_data == null: return
	var territory_item := depth_item(2)
	for tile in territory_tiles:
		var owner: int = int(territory_tiles[tile])
		if owner != CombatConfigScript.OWNER_NEUTRAL: RenderingServer.canvas_item_add_polygon(territory_item, diamond(tile, 0.78), PackedColorArray([Color("4b8ce0", 0.20) if owner == CombatConfigScript.OWNER_PLAYER else Color("de6464", 0.20)]))
	for unit_id in combat_data.sorted_unit_ids():
		var unit: Dictionary = combat_data.units[unit_id]
		if not bool(unit["alive"]): continue
		var center := IsoMathScript.tile_to_world(unit["tile"]) + Vector2(0, -8 if bool(unit["air"]) else 0)
		var color: Color = CombatConfigScript.UNIT_DATA[int(unit["type"])]["color"]
		if int(unit["owner"]) == CombatConfigScript.OWNER_AI: color = color.darkened(0.35).lerp(Color("ed6b6b"), 0.55)
		draw_unit_symbol(center, int(unit["type"]), color, unit["tile"])
		if unit_id == combat_data.selected_unit_id: draw_arc(center, 12.0, 0.0, TAU, 16, Color("fff0a3"), 2.0)
	if strategic_data != null:
		for missile_id in strategic_data.missiles:
			var missile: Dictionary = strategic_data.missiles[missile_id]
			if bool(missile["alive"]):
				draw_circle(strategic_data.missile_visual_position(missile) + Vector2(0, -14), 4.0, Color("ffcc66"))
		for marker in strategic_data.impact_markers:
			draw_blast_outline(marker["tile"], Color("ffb347"))
		if missile_preview_active:
			draw_blast_preview(missile_preview_tile)
			draw_missile_trajectory(strategic_data.selected_silo, missile_preview_tile)

func draw_blast_preview(center_tile: Vector2i) -> void:
	for tile in strategic_data.blast_tiles(center_tile):
		var occupied: bool = combat_data.unit_at(tile) >= 0 or (strategic_data.city_data != null and strategic_data.city_data.get_building(tile) != 0)
		draw_polyline(diamond(tile, 0.88), Color("ff7262", 0.72) if occupied else Color("ffe28a", 0.30), 1.4, true)
	draw_blast_outline(center_tile, Color("ffe28a"))
	draw_circle(IsoMathScript.tile_to_world(center_tile), 4.0, Color("fff3b0"))

func draw_blast_outline(center_tile: Vector2i, color: Color) -> void:
	var center := IsoMathScript.tile_to_world(center_tile)
	var radius := IsoMathScript.HALF_WIDTH * float(StrategicConfigScript.MISSILE_BLAST_RADIUS + 1)
	var segments := 32
	for segment in segments:
		if segment % 2 == 0:
			var start := TAU * float(segment) / segments
			var finish := TAU * float(segment + 1) / segments
			draw_arc(center, radius, start, finish, 3, color, 2.5, true)

func draw_missile_trajectory(source_tile: Vector2i, target_tile: Vector2i) -> void:
	if not map_data.is_valid(source_tile) or not map_data.is_valid(target_tile): return
	var segments := 28
	for segment in segments:
		if segment % 2 != 0: continue
		var start_progress := float(segment) / segments
		var end_progress := float(segment + 1) / segments
		var start := ballistic_point(source_tile, target_tile, start_progress)
		var finish := ballistic_point(source_tile, target_tile, end_progress)
		draw_line(start, finish, Color("fff0ad", 0.92), 2.0, true)

func ballistic_point(source_tile: Vector2i, target_tile: Vector2i, progress: float) -> Vector2:
	return StrategicConfigScript.ballistic_world_position(source_tile, target_tile, progress)

func draw_unit_symbol(center: Vector2, unit_type: int, color: Color, tile: Vector2i = Vector2i.ZERO) -> void:
	var cell: Vector2i = UNIT_CELLS.get(unit_type, Vector2i.ZERO)
	var source := Rect2(Vector2(cell) * UNIT_CELL_SIZE, UNIT_CELL_SIZE)
	var air_unit := unit_type >= 5
	var size := Vector2(66, 66) if air_unit else Vector2(54, 54)
	# Keep the bottom of a ground sprite on its tile. Aircraft remain compact and
	# are already lifted by the authoritative air-unit offset in _draw().
	var target := Rect2(center - Vector2(size.x * 0.5, size.y * 0.92), size)
	var item := depth_item(800 if air_unit else IsoMathScript.sprite_depth(tile) + 1)
	RenderingServer.canvas_item_add_texture_rect_region(item, target, UNIT_ATLAS.get_rid(), source)
	# Ownership is shown independently of sprite coloration, retaining clear
	# player/AI readability without replacing the unit silhouette with a marker.
	draw_arc(center + Vector2(0, 2), 10.0, 0.0, TAU, 12, color, 1.6)

func diamond(tile: Vector2i, scale: float) -> PackedVector2Array:
	var center := IsoMathScript.tile_to_world(tile)
	return PackedVector2Array([center + Vector2(0, -IsoMathScript.HALF_HEIGHT * scale), center + Vector2(IsoMathScript.HALF_WIDTH * scale, 0), center + Vector2(0, IsoMathScript.HALF_HEIGHT * scale), center + Vector2(-IsoMathScript.HALF_WIDTH * scale, 0)])
