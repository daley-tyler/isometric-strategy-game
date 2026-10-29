class_name IsoMath
extends RefCounted

const TILE_WIDTH := 64.0
const TILE_HEIGHT := 32.0
const HALF_WIDTH := TILE_WIDTH * 0.5
const HALF_HEIGHT := TILE_HEIGHT * 0.5

static func diamond(center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	return PackedVector2Array([center + Vector2(0, -HALF_HEIGHT), center + Vector2(HALF_WIDTH, 0), center + Vector2(0, HALF_HEIGHT), center + Vector2(-HALF_WIDTH, 0)])

static func screen_to_tile(screen: Vector2, canvas: Transform2D, map_size: Vector2i) -> Vector2i:
	return world_to_tile(canvas.affine_inverse() * screen, map_size)

static func sprite_depth(tile: Vector2i) -> int:
	return 100 + (tile.x + tile.y) * 2

static func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2((tile.x - tile.y) * HALF_WIDTH, (tile.x + tile.y) * HALF_HEIGHT)

static func continuous_tile_at(world_position: Vector2) -> Vector2:
	var horizontal := world_position.x / HALF_WIDTH
	var vertical := world_position.y / HALF_HEIGHT
	return Vector2((horizontal + vertical) * 0.5, (vertical - horizontal) * 0.5)

static func point_in_tile(world_position: Vector2, tile: Vector2i) -> bool:
	var local := world_position - tile_to_world(tile)
	return absf(local.x) / HALF_WIDTH + absf(local.y) / HALF_HEIGHT <= 1.00001

static func world_to_tile(world_position: Vector2, map_size: Vector2i) -> Vector2i:
	var continuous := continuous_tile_at(world_position)
	var base := Vector2i(floori(continuous.x), floori(continuous.y))
	var closest := Vector2i(-1, -1)
	var closest_distance := INF
	# The inverse transform gives a nearby cell; testing its small neighborhood makes
	# border picks deterministic and avoids visual/selection disagreement.
	for y_offset in range(-1, 3):
		for x_offset in range(-1, 3):
			var candidate := base + Vector2i(x_offset, y_offset)
			if candidate.x < 0 or candidate.y < 0 or candidate.x >= map_size.x or candidate.y >= map_size.y:
				continue
			if point_in_tile(world_position, candidate):
				var delta := world_position - tile_to_world(candidate)
				var distance := absf(delta.x) / HALF_WIDTH + absf(delta.y) / HALF_HEIGHT
				if distance < closest_distance:
					closest = candidate
					closest_distance = distance
	return closest
