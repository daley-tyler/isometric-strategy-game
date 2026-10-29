class_name StrategicConfig
extends RefCounted

const IsoMathScript = preload("res://scripts/iso_math.gd")

const MISSILE_COST_MONEY := 45.0
const MISSILE_COST_MATERIALS := 6.0
const MISSILE_COST_SUPPLIES := 4.0
const MISSILE_COST_POWER := 3.0
const MISSILE_PRODUCTION_TICKS := 3
const SILO_CAPACITY := 3
const SILO_LAUNCH_COOLDOWN := 3
const MISSILE_SPEED_TILES_PER_TICK := 20.0
const MISSILE_MIN_FLIGHT_TICKS := 2
const MISSILE_MAX_FLIGHT_TICKS := 10
const MISSILE_BLAST_RADIUS := 1
const MISSILE_ARC_HEIGHT := 96.0
const SAM_RANGE := 5
const SAM_COOLDOWN_TICKS := 2
# Stable rule rather than runtime randomness: odd missile ids are intercepted.
const SAM_INTERCEPT_ODD_IDS := true

static func missile_arc_height(progress: float) -> float:
	var normalized := clampf(progress, 0.0, 1.0)
	return MISSILE_ARC_HEIGHT * 4.0 * normalized * (1.0 - normalized)

static func flight_duration_ticks(source: Vector2i, target: Vector2i) -> int:
	var distance := Vector2(source).distance_to(Vector2(target))
	return clampi(ceili(distance / MISSILE_SPEED_TILES_PER_TICK), MISSILE_MIN_FLIGHT_TICKS, MISSILE_MAX_FLIGHT_TICKS)

static func ballistic_world_position(source: Vector2i, target: Vector2i, progress: float) -> Vector2:
	var normalized := clampf(progress, 0.0, 1.0)
	return IsoMathScript.tile_to_world(source).lerp(IsoMathScript.tile_to_world(target), normalized) + Vector2(0.0, -missile_arc_height(normalized))
