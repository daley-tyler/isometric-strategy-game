class_name TileMarker
extends Node2D

const IsoMathScript = preload("res://scripts/iso_math.gd")

var marker_color := Color.WHITE
var active := false
var displayed_tile := Vector2i(-1, -1)

func _init() -> void:
	z_index = 2000

func set_tile(tile: Vector2i, color: Color) -> void:
	if active and displayed_tile == tile and marker_color == color:
		return
	global_position = IsoMathScript.tile_to_world(tile)
	marker_color = color
	displayed_tile = tile
	active = true
	queue_redraw()

func clear() -> void:
	if not active:
		return
	active = false
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	var diamond := IsoMathScript.diamond()
	diamond.append(diamond[0])
	draw_polyline(diamond, marker_color, 3.0, true)
