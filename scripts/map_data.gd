class_name MapData
extends RefCounted

enum Terrain { PLAINS, FOREST, HILL, RIVER, COAST }
enum ResourceDeposit { NONE, IRON, STONE, OIL }

const MAP_SIZE := Vector2i(128, 128)
const SEED := 20260912
const CARDINAL_DIRECTIONS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var size: Vector2i
var seed: int
var terrain: PackedByteArray
var bridges: PackedByteArray
var deposits: PackedByteArray
var markers: PackedByteArray
var scorched: PackedByteArray
var player_capital := Vector2i(-1, -1)
var ai_capital := Vector2i(-1, -1)

func _init(map_size: Vector2i = MAP_SIZE, map_seed: int = SEED, generate_now: bool = true) -> void:
	size = map_size
	seed = map_seed
	terrain.resize(size.x * size.y)
	bridges.resize(size.x * size.y)
	deposits.resize(size.x * size.y)
	markers.resize(size.x * size.y)
	scorched.resize(size.x * size.y)
	if generate_now:
		generate()

func generate() -> void:
	bridges.fill(0)
	deposits.fill(ResourceDeposit.NONE)
	markers.fill(0)
	scorched.fill(0)
	for y in size.y:
		for x in size.x:
			var tile := Vector2i(x, y)
			if x < coast_width_at(y):
				terrain[index(tile)] = Terrain.COAST
			else:
				var variation: int = positive_hash(tile, 101) % 100
				terrain[index(tile)] = Terrain.FOREST if variation < 20 else Terrain.HILL if variation < 31 else Terrain.PLAINS
	generate_river()
	generate_bridges()
	generate_deposits()
	generate_capitals()

func index(tile: Vector2i) -> int:
	return tile.y * size.x + tile.x

func is_valid(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < size.x and tile.y < size.y

func get_terrain(tile: Vector2i) -> int:
	return terrain[index(tile)]

func is_water(tile: Vector2i) -> bool:
	if not is_valid(tile):
		return false
	var terrain_type := get_terrain(tile)
	return terrain_type == Terrain.RIVER or terrain_type == Terrain.COAST

func is_land(tile: Vector2i) -> bool:
	if not is_valid(tile):
		return false
	var terrain_type := get_terrain(tile)
	return terrain_type == Terrain.PLAINS or terrain_type == Terrain.FOREST or terrain_type == Terrain.HILL

func is_river(tile: Vector2i) -> bool:
	return is_valid(tile) and get_terrain(tile) == Terrain.RIVER

func is_bridge(tile: Vector2i) -> bool:
	return is_valid(tile) and bridges[index(tile)] != 0

func is_capital_marker(tile: Vector2i) -> bool:
	return tile == player_capital or tile == ai_capital

func has_marker(tile: Vector2i) -> bool:
	return is_valid(tile) and markers[index(tile)] != 0

func can_place_marker(tile: Vector2i) -> bool:
	return is_traversable_ground(tile) and not has_marker(tile)

func place_marker(tile: Vector2i) -> bool:
	if not can_place_marker(tile):
		return false
	markers[index(tile)] = 1
	return true

func remove_marker(tile: Vector2i) -> bool:
	if not has_marker(tile):
		return false
	markers[index(tile)] = 0
	return true

func marker_count() -> int:
	var count := 0
	for value in markers:
		count += value
	return count

func has_scorch(tile: Vector2i) -> bool:
	return is_valid(tile) and scorched[index(tile)] != 0

func mark_scorched(tile: Vector2i) -> bool:
	if not is_valid(tile) or has_scorch(tile):
		return false
	scorched[index(tile)] = 1
	return true

func scorch_count() -> int:
	var count := 0
	for value in scorched: count += value
	return count

func get_resource_deposit(tile: Vector2i) -> int:
	if not is_valid(tile):
		return ResourceDeposit.NONE
	return deposits[index(tile)]

func has_resource_deposit(tile: Vector2i) -> bool:
	return get_resource_deposit(tile) != ResourceDeposit.NONE

func is_traversable_ground(tile: Vector2i) -> bool:
	return is_valid(tile) and (is_bridge(tile) or is_land(tile))

func are_ground_tiles_connected(from: Vector2i, to: Vector2i) -> bool:
	if not is_traversable_ground(from) or not is_traversable_ground(to):
		return false
	var visited := PackedByteArray()
	visited.resize(size.x * size.y)
	var queue: Array[Vector2i] = [from]
	visited[index(from)] = 1
	var cursor := 0
	while cursor < queue.size():
		var current: Vector2i = queue[cursor]
		if current == to:
			return true
		cursor += 1
		for direction in CARDINAL_DIRECTIONS:
			var next: Vector2i = current + direction
			if is_traversable_ground(next) and visited[index(next)] == 0:
				visited[index(next)] = 1
				queue.append(next)
	return false

func terrain_checksum() -> int:
	return checksum_values(terrain)

func world_checksum() -> int:
	var result := terrain_checksum()
	result = combine_checksum(result, checksum_values(bridges))
	result = combine_checksum(result, checksum_values(deposits))
	result = combine_checksum(result, checksum_values(markers))
	result = combine_checksum(result, checksum_values(scorched))
	result = combine_checksum(result, player_capital.x)
	result = combine_checksum(result, player_capital.y)
	result = combine_checksum(result, ai_capital.x)
	return combine_checksum(result, ai_capital.y)

func checksum() -> int:
	return world_checksum()

func coast_width_at(y: int) -> int:
	return 3 + positive_hash(Vector2i(0, y), 17) % 4

func generate_river() -> void:
	var river_y := 18 + positive_hash(Vector2i(1, 1), 71) % (size.y - 36)
	for x in range(size.x - 1, 5, -1):
		var previous_y := river_y
		if x % 4 == 0:
			river_y = clampi(river_y + positive_hash(Vector2i(x, river_y), 73) % 3 - 1, 8, size.y - 9)
			if river_y != previous_y:
				terrain[index(Vector2i(x + 1, river_y))] = Terrain.RIVER
		terrain[index(Vector2i(x, river_y))] = Terrain.RIVER

func generate_bridges() -> void:
	for bridge_x in [24, 64, 104]:
		for y in size.y:
			var tile := Vector2i(bridge_x, y)
			if is_river(tile):
				bridges[index(tile)] = 1
				break

func generate_deposits() -> void:
	var placed := 0
	for y in range(8, size.y - 8):
		for x in range(8, size.x - 8):
			var tile := Vector2i(x, y)
			var hash_value := positive_hash(tile, 131)
			if placed < 12 and hash_value % 1000 < 12 and is_land(tile) and can_place_deposit(tile):
				deposits[index(tile)] = ResourceDeposit.IRON + hash_value % 3
				placed += 1

func can_place_deposit(candidate: Vector2i) -> bool:
	for y in range(maxi(candidate.y - 8, 0), mini(candidate.y + 9, size.y)):
		for x in range(maxi(candidate.x - 8, 0), mini(candidate.x + 9, size.x)):
			if has_resource_deposit(Vector2i(x, y)):
				return false
	return true

func generate_capitals() -> void:
	player_capital = find_land_near(Vector2i(28, 28))
	ai_capital = find_land_near(Vector2i(size.x - 28, size.y - 28))
	if not are_ground_tiles_connected(player_capital, ai_capital):
		ai_capital = find_reachable_land_near(Vector2i(size.x - 28, size.y - 28), player_capital)

func find_land_near(preferred: Vector2i) -> Vector2i:
	for radius in range(0, size.x):
		for y in range(preferred.y - radius, preferred.y + radius + 1):
			for x in range(preferred.x - radius, preferred.x + radius + 1):
				var candidate := Vector2i(x, y)
				if is_land(candidate):
					return candidate
	return Vector2i(-1, -1)

func find_reachable_land_near(preferred: Vector2i, origin: Vector2i) -> Vector2i:
	for radius in range(0, size.x):
		for y in range(preferred.y - radius, preferred.y + radius + 1):
			for x in range(preferred.x - radius, preferred.x + radius + 1):
				var candidate := Vector2i(x, y)
				if is_land(candidate) and are_ground_tiles_connected(origin, candidate):
					return candidate
	return Vector2i(-1, -1)

func positive_hash(tile: Vector2i, salt: int) -> int:
	var hash_value: int = seed + salt * 374761393
	hash_value = hash_value * 1664525 + tile.x * 1013904223 + tile.y * 69069
	hash_value = hash_value ^ (hash_value >> 16)
	hash_value = hash_value * 2246822519
	hash_value = hash_value ^ (hash_value >> 13)
	return absi(hash_value)

func checksum_values(values: PackedByteArray) -> int:
	var result := 0
	for value in values:
		result = combine_checksum(result, value)
	return result

func combine_checksum(current: int, value: int) -> int:
	return (current * 31 + value) % 2147483647
