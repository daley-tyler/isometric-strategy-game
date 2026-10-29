class_name DebugOverlay
extends CanvasLayer

var label := Label.new()
var last_stats := ""

func _ready() -> void:
	label.position = Vector2(14, 12)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("e8f2e8"))
	label.add_theme_color_override("font_shadow_color", Color("17231d"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)

func update_stats(fps: float, frame_time_ms: float, visible_chunks: int, rendered_tiles: int, zoom: float, hovered: Vector2i, selected: Vector2i, status: String = "", city_summary: String = "") -> void:
	var city_status := "" if status.is_empty() else "\nStatus: %s" % status
	var summary := "" if city_summary.is_empty() else "\n%s" % city_summary
	var stats := "FPS: %.0f  Frame: %.2f ms\nChunks: %d  Tiles: %d  Zoom: %.2fx\nHover: %s  Selected: %s%s%s\nR road · 1 res · 2 commercial · 3 power · 4 water · 5 fire · B bulldoze\nF farm · M materials · Y refinery · I import · G defense · U university · L lab\nN barracks · V vehicle · O drone · H airbase · 7 SAM · 8 silo · T research\nF1–F7 deploy · click unit · right-click Move/Attack · G Defend · Space Stop · Esc clear · F8 dev AI\nF9 manufacture missile · F10 target mode then left-click any in-bounds tile" % [fps, frame_time_ms, visible_chunks, rendered_tiles, zoom, hovered, selected, city_status, summary]
	if stats == last_stats:
		return
	last_stats = stats
	label.text = stats
