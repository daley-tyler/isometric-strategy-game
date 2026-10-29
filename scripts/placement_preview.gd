extends Node2D

const Art = preload("res://scripts/building_overlay.gd")
const Iso = preload("res://scripts/iso_math.gd")
var anchor := Vector2i(-1, -1)
var footprint: Array[Vector2i] = []
var reason := ""
var building_type := 0
var seed_value := 0

func _init() -> void:
	z_index = 1500

func update_preview(city, tile: Vector2i, kind: int) -> void:
	var next_reason: String = city.building_placement_reason(tile, kind) if kind != 0 else ""
	if tile == anchor and kind == building_type and next_reason == reason and seed_value == city.map_data.seed: return
	anchor = tile
	building_type = kind
	reason = next_reason
	seed_value = city.map_data.seed
	footprint.clear()
	if kind != 0: footprint.assign(city.get_building_footprint_tiles(kind, tile))
	queue_redraw()

func clear() -> void:
	building_type = 0
	footprint.clear()
	anchor = Vector2i(-1, -1)
	reason = ""
	queue_redraw()

func _draw() -> void:
	if building_type == 0 or anchor.x < 0: return
	var valid := reason.is_empty()
	var accent := Color("75d99c") if valid else Color("ff6464")
	for tile in footprint:
		var diamond := Iso.diamond(Iso.tile_to_world(tile))
		draw_colored_polygon(diamond, Color(accent, 0.23))
		diamond.append(diamond[0])
		draw_polyline(diamond, accent, 2.0, true)
	var art := Art.sprite_metadata(anchor, building_type, seed_value)
	draw_texture_rect_region(Art.BUILDING_ATLAS, art.target, art.source, Color(0.8, 0.85, 0.83, 0.55) if valid else Color(1.0, 0.35, 0.35, 0.55))
