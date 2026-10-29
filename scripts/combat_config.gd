class_name CombatConfig
extends RefCounted

# Numeric values deliberately mirror CitySimulation.UnitType; combat does not own production.
const OWNER_NEUTRAL := 0
const OWNER_PLAYER := 1
const OWNER_AI := 2

const COMMAND_IDLE := 0
const COMMAND_MOVE := 1
const COMMAND_ATTACK := 2
const COMMAND_DEFEND := 3
const COMMAND_STOP := 4

const CAPTURE_TICKS := 2
const CAPITAL_CAPTURE_TICKS := 2
const CAPTURE_RADIUS := 1
const ARTILLERY_MIN_RANGE := 2
const ARTILLERY_MAX_RANGE := 3
const ARTILLERY_SPLASH_RADIUS := 1
const ARTILLERY_COOLDOWN_TICKS := 2

const UNIT_DATA := {
	1: {"name": "Infantry", "health": 32.0, "armor": 1.0, "damage": 7.0, "range": 1, "speed": 1.0, "air": false, "color": Color("d9e8bf")},
	2: {"name": "Tank", "health": 58.0, "armor": 4.0, "damage": 12.0, "range": 1, "speed": 1.0, "air": false, "color": Color("9cc6a6")},
	3: {"name": "Artillery", "health": 38.0, "armor": 1.0, "damage": 10.0, "range": 3, "speed": 1.0, "air": false, "color": Color("d7c296")},
	4: {"name": "Robot", "health": 52.0, "armor": 3.0, "damage": 11.0, "range": 1, "speed": 1.0, "air": false, "color": Color("a9b9d8")},
	5: {"name": "Recon", "health": 22.0, "armor": 0.0, "damage": 3.0, "range": 2, "speed": 2.0, "air": true, "color": Color("92d6e8")},
	6: {"name": "Bomber", "health": 36.0, "armor": 1.0, "damage": 14.0, "range": 2, "speed": 2.0, "air": true, "color": Color("e2b193")},
	7: {"name": "Fighter", "health": 32.0, "armor": 2.0, "damage": 10.0, "range": 1, "speed": 2.0, "air": true, "color": Color("d5a5d8")},
}

static func terrain_move_cost(terrain: int) -> int:
	# Forest and hills take an extra fixed simulation tick for ground formations.
	return 2 if terrain == 1 or terrain == 2 else 1

static func defense_multiplier(terrain: int) -> float:
	return 0.85 if terrain == 1 else 0.80 if terrain == 2 else 1.0

static func command_name(command: int) -> String:
	return ["Idle", "Move", "Attack", "Defend", "Stop"][clampi(command, 0, 4)]
