extends SceneTree

const Map = preload("res://scripts/map_data.gd")
const City = preload("res://scripts/city_simulation.gd")
const Combat = preload("res://scripts/combat_simulation.gd")
const Strategic = preload("res://scripts/strategic_simulation.gd")
const Config = preload("res://scripts/strategic_config.gd")
const Persistence = preload("res://scripts/persistence_manager.gd")
const Campaign = preload("res://scripts/campaign_state.gd")
const AI = preload("res://scripts/ai_campaign_controller.gd")
const World = preload("res://scripts/world_renderer.gd")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func setup() -> Dictionary:
	var map = Map.new()
	var city = City.new(map)
	var combat = Combat.new(map, city)
	var strategic = Strategic.new(map, city, combat)
	var tile: Vector2i = map.player_capital
	city.buildings[city.index(tile)] = City.Building.MISSILE_SILO
	city.industry_buildings.append(tile)
	city.resources[City.LedgerResource.MONEY] = Config.MISSILE_COST_MONEY
	city.resources[City.LedgerResource.MATERIALS] = Config.MISSILE_COST_MATERIALS
	city.resources[City.LedgerResource.MILITARY_SUPPLIES] = Config.MISSILE_COST_SUPPLIES
	city.resources[City.LedgerResource.ELECTRICITY] = Config.MISSILE_COST_POWER
	return {"map": map, "city": city, "combat": combat, "strategic": strategic, "tile": tile}

func run() -> void:
	missile_resource_competition()
	destroyed_silo_cancellation()
	ai_order_round_trip()
	ai_route_reuse()
	city_lifetime()
	batched_chunk_refresh()
	if failures.is_empty():
		print("Reliability validation passed: missile ledger safety, destroyed silos, AI order persistence, city lifetime, and batched rendering.")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func missile_resource_competition() -> void:
	# Resources can be spent by construction or normal manufacturing while a
	# missile is queued. Check each ledger independently, then resume normally.
	for resource in [City.LedgerResource.MONEY, City.LedgerResource.MATERIALS, City.LedgerResource.MILITARY_SUPPLIES]:
		var s := setup()
		expect(s.strategic.queue_missile(s.tile), "Funded missile must queue")
		var available: float = s.city.resources[resource]
		s.city.resources[resource] = 0.0
		var before: PackedFloat64Array = s.city.resources.duplicate()
		for tick in Config.MISSILE_PRODUCTION_TICKS + 2:
			s.strategic.tick()
		expect(s.city.resources == before, "A starved missile must not debit any resources")
		expect(int(s.strategic.ensure_silo(s.tile)["stored"]) == 0, "A starved missile must not complete")
		s.city.resources[resource] = available
		s.strategic.tick()
		expect(int(s.strategic.ensure_silo(s.tile)["stored"]) == 1, "A stalled missile must resume after resupply")
		for tick in 3:
			s.strategic.tick()
		expect(int(s.strategic.ensure_silo(s.tile)["stored"]) == 1, "Completion must happen exactly once")
		expect(s.city.resources[City.LedgerResource.MONEY] == 0.0 and s.city.resources[City.LedgerResource.MATERIALS] == 0.0 and s.city.resources[City.LedgerResource.MILITARY_SUPPLIES] == 0.0, "Completion must debit exact costs without negative balances")

func destroyed_silo_cancellation() -> void:
	for destroy in [false, true]:
		var s := setup()
		expect(s.strategic.queue_missile(s.tile), "Missile must queue before silo removal")
		var before: PackedFloat64Array = s.city.resources.duplicate()
		if destroy:
			s.city.destroy_structure(s.tile)
		else:
			s.city.bulldoze(s.tile)
		for tick in Config.MISSILE_PRODUCTION_TICKS + 1:
			s.strategic.tick()
		expect(not s.strategic.silos.has(s.tile), "Removed silo must lose its production and storage state")
		expect(s.city.resources == before, "Removed silo must not spend resources")

func ai_order_round_trip() -> void:
	var s := setup()
	var ai = AI.new(s.map, s.city, s.combat, s.strategic)
	var id: int = s.combat.spawn_developer_unit(2, City.UnitType.INFANTRY, s.map.ai_capital)
	s.combat.units[id]["strategic_managed"] = true
	var persistence = Persistence.new()
	# JSON conversion exercises the actual on-disk number and dictionary format.
	var document: Dictionary = JSON.parse_string(JSON.stringify(persistence.create_save_data(s.map, s.city, s.combat, s.strategic, Campaign.new(), "manual", -1, ai)))
	var loaded: Dictionary = persistence.reconstruct(document)
	expect(not loaded.is_empty(), "AI campaign must reconstruct")
	if loaded.is_empty():
		return
	expect(bool(loaded.combat.get_unit(id).get("strategic_managed", false)), "Save/load must retain AI strategic management")
	s.combat.tick()
	loaded.combat.tick()
	expect(loaded.combat.units == s.combat.units, "The next combat tick after load must match uninterrupted execution")
	# Earlier version-1 saves omitted the marker; their AI-owned units must be
	# reattached when the AI section is present.
	for unit in document.combat.units:
		unit.erase("strategic_managed")
	var legacy: Dictionary = persistence.reconstruct(document)
	expect(bool(legacy.combat.get_unit(id).get("strategic_managed", false)), "Legacy campaign saves must recover AI management")

func city_lifetime() -> void:
	var map = Map.new()
	var player = City.new(map)
	var enemy = City.new(map)
	player.foreign_city_data = enemy
	enemy.foreign_city_data = player
	var player_ref: WeakRef = weakref(player)
	var enemy_ref: WeakRef = weakref(enemy)
	player = null
	enemy = null
	expect(player_ref.get_ref() == null and enemy_ref.get_ref() == null, "Mutual occupancy queries must not retain discarded city simulations")

func ai_route_reuse() -> void:
	var s := setup()
	var ai = AI.new(s.map, s.city, s.combat, s.strategic)
	for index in 5:
		s.combat.spawn_developer_unit(2, City.UnitType.INFANTRY, s.map.ai_capital)
	ai.assign_force_orders()
	var before: int = s.combat.path_rebuild_count
	var attacker: Dictionary = s.combat.get_unit(3)
	attacker["move_wait"] = 1
	ai.assign_force_orders()
	expect(before == 3 and s.combat.path_rebuild_count == before, "Unchanged AI destinations must reuse the three attacking units' routes")
	expect(int(attacker["move_wait"]) == 1, "Repeated AI planning must preserve terrain movement delay")

func batched_chunk_refresh() -> void:
	var s := setup()
	var world = World.new()
	root.add_child(world)
	world.configure(s.map, s.city)
	# This blast crosses both chunk axes and includes several changed tiles in
	# each affected chunk. Every chunk must see the final authoritative state.
	var tiles: Array[Vector2i] = s.strategic.apply_blast(Vector2i(16, 16))
	tiles.append(tiles[0])
	tiles.append(Vector2i(-1, -1))
	var before: Array[int] = []
	for chunk in world.chunks:
		before.append(chunk.visual_rebuild_count)
	world.refresh_tiles(tiles)
	var rebuilds := 0
	for index in world.chunks.size():
		var chunk = world.chunks[index]
		var expected := 0
		for tile in tiles:
			if s.map.is_valid(tile) and Vector2i(tile.x / 16, tile.y / 16) == chunk.chunk:
				expected = 1
		var actual: int = chunk.visual_rebuild_count - before[index]
		expect(actual == expected, "Batch must rebuild each changed chunk once and leave all other meshes cached")
		rebuilds += actual
	expect(rebuilds == 3, "Cross-shaped boundary blast must rebuild exactly three chunks")
	print("Chunk refresh check: %d blast tiles, %d mesh rebuilds" % [tiles.size() - 2, rebuilds])
	world.free()
