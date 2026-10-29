class_name BuildingOverlay
extends Node2D

const IsoMathScript = preload("res://scripts/iso_math.gd")
const CitySimulationScript = preload("res://scripts/city_simulation.gd")
const BUILDING_ATLAS: Texture2D = preload("res://assets/buildings/isometric_buildings_atlas_v1.png")

# The source art is a 4 x 5 transparent atlas. Drawing regions from one cached
# texture keeps the world visual layer lightweight while all construction state
# remains authoritative CitySimulation data.
const CELL_SIZE := Vector2(311.5, 252.6)
const BUILDING_CELLS := {
	CitySimulationScript.Building.POWER_PLANT: Vector2i(2, 0),
	CitySimulationScript.Building.WATER_FACILITY: Vector2i(3, 0),
	CitySimulationScript.Building.FIRE_STATION: Vector2i(0, 1),
	CitySimulationScript.Building.RESIDENTIAL: Vector2i(0, 0),
	CitySimulationScript.Building.COMMERCIAL: Vector2i(1, 0),
	CitySimulationScript.Building.FARM: Vector2i(1, 1),
	CitySimulationScript.Building.MATERIALS_PLANT: Vector2i(2, 1),
	CitySimulationScript.Building.REFINERY: Vector2i(3, 1),
	CitySimulationScript.Building.IMPORT_DEPOT: Vector2i(0, 2),
	CitySimulationScript.Building.DEFENSE_FACTORY: Vector2i(1, 2),
	CitySimulationScript.Building.UNIVERSITY: Vector2i(2, 2),
	CitySimulationScript.Building.RESEARCH_LAB: Vector2i(3, 2),
	CitySimulationScript.Building.BARRACKS: Vector2i(0, 3),
	CitySimulationScript.Building.VEHICLE_FACTORY: Vector2i(1, 3),
	CitySimulationScript.Building.DRONE_FACTORY: Vector2i(2, 3),
	CitySimulationScript.Building.AIRBASE: Vector2i(3, 3),
	CitySimulationScript.Building.SAM_SITE: Vector2i(0, 4),
	CitySimulationScript.Building.MISSILE_SILO: Vector2i(1, 4),
}
const COMMERCIAL_VARIANTS := [Vector2i(1, 0), Vector2i(2, 4), Vector2i(3, 4)]

var map_data
var city_data
var chunk := Vector2i.ZERO
var color_tint := Color.WHITE
var sprite_items: Array[RID] = []

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear_sprite_items()

func clear_sprite_items() -> void:
	for item in sprite_items: RenderingServer.free_rid(item)
	sprite_items.clear()

func configure(data, city, chunk_coordinate: Vector2i, tint: Color = Color.WHITE) -> void:
	map_data = data
	city_data = city
	chunk = chunk_coordinate
	color_tint = tint
	queue_redraw()

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	clear_sprite_items()
	if map_data == null or city_data == null:
		return
	var start := chunk * 16
	var finish := Vector2i(mini(start.x + 16, map_data.size.x), mini(start.y + 16, map_data.size.y))
	# Stable traversal; absolute sprite depth handles cross-chunk overlap.
	for diagonal in range(start.x + start.y, finish.x + finish.y - 1):
		for y in range(start.y, finish.y):
			var x := diagonal - y
			if x < start.x or x >= finish.x:
				continue
			var tile := Vector2i(x, y)
			var building_type: int = city_data.get_building(tile)
			if building_type != CitySimulationScript.Building.NONE:
				var art := sprite_metadata(tile, building_type, map_data.seed)
				var item := RenderingServer.canvas_item_create()
				RenderingServer.canvas_item_set_parent(item, get_canvas_item())
				RenderingServer.canvas_item_set_z_as_relative_to_parent(item, false)
				RenderingServer.canvas_item_set_z_index(item, IsoMathScript.sprite_depth(tile))
				RenderingServer.canvas_item_add_texture_rect_region(item, art.target, BUILDING_ATLAS.get_rid(), art.source, color_tint * art.tint)
				sprite_items.append(item)

func draw_building_sprite(tile: Vector2i, building_type: int) -> void:
	var art := sprite_metadata(tile, building_type, map_data.seed)
	draw_texture_rect_region(BUILDING_ATLAS, art.target, art.source, color_tint * art.tint)

static func sprite_metadata(tile: Vector2i, building_type: int, seed_value: int) -> Dictionary:
	var cell: Vector2i = BUILDING_CELLS.get(building_type, Vector2i.ZERO)
	var variant := posmod(tile.x * 31 + tile.y * 17 + seed_value, 3)
	if building_type == CitySimulationScript.Building.COMMERCIAL:
		cell = COMMERCIAL_VARIANTS[variant]
	var source := Rect2(Vector2(cell) * CELL_SIZE, CELL_SIZE)
	var row_edges := [0.0, 275.0, 520.0, 780.0, 1020.0, 1263.0]
	source.position.y = row_edges[cell.y]
	source.size.y = row_edges[cell.y + 1] - row_edges[cell.y]
	# Measured foot points in atlas coordinates: base center, not cell center.
	# Source art has unequal transparent padding, especially in its top row.
	var feet := [Vector2(155, 254), Vector2(462, 254), Vector2(769, 266), Vector2(1080, 265), Vector2(153, 506), Vector2(468, 508), Vector2(780, 506), Vector2(1096, 512), Vector2(165, 750), Vector2(479, 760), Vector2(788, 773), Vector2(1096, 773), Vector2(160, 991), Vector2(480, 990), Vector2(779, 1000), Vector2(1095, 1016), Vector2(153, 1230), Vector2(465, 1245), Vector2(794, 1250), Vector2(1103, 1250)]
	var foot: Vector2 = feet[cell.y * 4 + cell.x] - source.position
	var scale_factor := 0.22
	var target := Rect2(IsoMathScript.tile_to_world(tile) - foot * scale_factor, source.size * scale_factor)
	var tint := Color.WHITE
	if building_type == CitySimulationScript.Building.RESIDENTIAL:
		tint = Color.WHITE.lerp([Color("fff3d9"), Color("dff4ff"), Color("ffe3e8")][variant], 0.10)
	return {"source": source, "target": target, "foot": foot, "scale": scale_factor, "tint": tint}

func deterministic_variant(tile: Vector2i) -> int:
	return posmod(tile.x * 31 + tile.y * 17 + map_data.seed, 3)
