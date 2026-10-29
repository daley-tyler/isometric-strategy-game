class_name CityConfig
extends RefCounted

const TICK_SECONDS := 1.0
const STARTING_MONEY := 500.0
const POWER_PLANT_COST := 100.0
const WATER_FACILITY_COST := 80.0
const FIRE_STATION_COST := 60.0
const POWER_CAPACITY := 50.0
const RESIDENTIAL_CAPACITY := 8
const COMMERCIAL_JOBS := 6
const POWER_PER_DEVELOPMENT := 1.0
const TAX_PER_OCCUPIED_HOUSEHOLD := 0.5

# These numeric resource values intentionally match CitySimulation.LedgerResource.
const RESOURCE_MONEY := 0
const RESOURCE_WORKFORCE := 1
const RESOURCE_ELECTRICITY := 2
const RESOURCE_FOOD := 3
const RESOURCE_MATERIALS := 4
const RESOURCE_FUEL := 5
const RESOURCE_MILITARY_SUPPLIES := 6

const BUILDING_FARM := 6
const BUILDING_MATERIALS_PLANT := 7
const BUILDING_REFINERY := 8
const BUILDING_IMPORT_DEPOT := 9
const BUILDING_DEFENSE_FACTORY := 10
const BUILDING_UNIVERSITY := 11
const BUILDING_RESEARCH_LAB := 12
const BUILDING_BARRACKS := 13
const BUILDING_VEHICLE_FACTORY := 14
const BUILDING_DRONE_FACTORY := 15
const BUILDING_AIRBASE := 16
const BUILDING_SAM_SITE := 17
const BUILDING_MISSILE_SILO := 18

const TECH_NONE := 0
const TECH_INDUSTRIAL_EXPANSION := 1
const TECH_REFINING := 2
const TECH_DEFENSE_INDUSTRY := 3
const TECH_ADVANCED_MANUFACTURING := 4
const TECH_AUTOMATION := 5
const TECH_AEROSPACE := 6
const TECH_NEAR_FUTURE := 7
const TECH_COUNT := 8

const UNIT_NONE := 0
const UNIT_INFANTRY := 1
const UNIT_TANK := 2
const UNIT_ARTILLERY := 3
const UNIT_ROBOT := 4
const UNIT_RECON_DRONE := 5
const UNIT_BOMBER := 6
const UNIT_FIGHTER := 7
const UNIT_COUNT := 8

const IMPORT_DELAY_TICKS := 3
const IMPORT_QUANTITY := 10.0

# Construction, operating, unlock, and output data is intentionally centralized.
const BUILDING_DATA := {
	BUILDING_FARM: {"name": "Farm", "money_cost": 40.0, "material_cost": 0.0, "workforce": 1, "power": 1.0, "road": true, "water": true, "unlock": TECH_NONE, "output": RESOURCE_FOOD, "rate": 4.0},
	BUILDING_MATERIALS_PLANT: {"name": "Materials Plant", "money_cost": 65.0, "material_cost": 0.0, "workforce": 2, "power": 2.0, "road": true, "water": true, "unlock": TECH_INDUSTRIAL_EXPANSION, "output": RESOURCE_MATERIALS, "rate": 3.0, "deposit": [1, 2]},
	BUILDING_REFINERY: {"name": "Refinery", "money_cost": 75.0, "material_cost": 3.0, "workforce": 2, "power": 3.0, "road": true, "water": true, "unlock": TECH_REFINING, "output": RESOURCE_FUEL, "rate": 2.0, "deposit": [3]},
	BUILDING_IMPORT_DEPOT: {"name": "Import Depot", "money_cost": 50.0, "material_cost": 0.0, "workforce": 1, "power": 1.0, "road": true, "water": true, "unlock": TECH_NONE},
	BUILDING_DEFENSE_FACTORY: {"name": "Defense Factory", "money_cost": 100.0, "material_cost": 5.0, "workforce": 3, "power": 4.0, "road": true, "water": true, "unlock": TECH_DEFENSE_INDUSTRY, "output": RESOURCE_MILITARY_SUPPLIES, "rate": 2.0, "input": RESOURCE_MATERIALS, "input_rate": 1.0, "operating_money": 1.0},
	BUILDING_UNIVERSITY: {"name": "University", "money_cost": 80.0, "material_cost": 0.0, "workforce": 1, "power": 2.0, "road": true, "water": true, "unlock": TECH_NONE, "research_rate": 1.0},
	BUILDING_RESEARCH_LAB: {"name": "Research Laboratory", "money_cost": 110.0, "material_cost": 2.0, "workforce": 2, "power": 3.0, "road": true, "water": true, "unlock": TECH_INDUSTRIAL_EXPANSION, "research_rate": 1.0},
	BUILDING_BARRACKS: {"name": "Barracks", "money_cost": 70.0, "material_cost": 0.0, "workforce": 1, "power": 1.0, "road": true, "water": true, "unlock": TECH_NONE},
	BUILDING_VEHICLE_FACTORY: {"name": "Vehicle Factory", "money_cost": 140.0, "material_cost": 10.0, "workforce": 3, "power": 5.0, "road": true, "water": true, "unlock": TECH_ADVANCED_MANUFACTURING},
	BUILDING_DRONE_FACTORY: {"name": "Drone Factory", "money_cost": 150.0, "material_cost": 10.0, "workforce": 3, "power": 5.0, "road": true, "water": true, "unlock": TECH_AUTOMATION},
	BUILDING_AIRBASE: {"name": "Airbase", "money_cost": 180.0, "material_cost": 15.0, "workforce": 3, "power": 6.0, "road": true, "water": true, "unlock": TECH_AEROSPACE},
	BUILDING_SAM_SITE: {"name": "SAM Site", "money_cost": 120.0, "material_cost": 10.0, "workforce": 1, "power": 3.0, "road": true, "water": true, "unlock": TECH_NEAR_FUTURE},
	BUILDING_MISSILE_SILO: {"name": "Missile Silo", "money_cost": 180.0, "material_cost": 15.0, "workforce": 2, "power": 4.0, "road": true, "water": true, "unlock": TECH_NEAR_FUTURE},
}

const TECHNOLOGY_DATA := {
	# The University owns the early branch, including the research that unlocks
	# the Laboratory. Advanced technologies explicitly require the Laboratory,
	# so the progression has a clear one-way handoff with no circular dependency.
	TECH_INDUSTRIAL_EXPANSION: {"name": "Industrial Expansion", "prerequisite": TECH_NONE, "cost": 3.0, "facility": BUILDING_UNIVERSITY},
	TECH_REFINING: {"name": "Refining", "prerequisite": TECH_INDUSTRIAL_EXPANSION, "cost": 3.0, "facility": BUILDING_UNIVERSITY},
	TECH_DEFENSE_INDUSTRY: {"name": "Defense Industry", "prerequisite": TECH_INDUSTRIAL_EXPANSION, "cost": 3.0, "facility": BUILDING_UNIVERSITY},
	TECH_ADVANCED_MANUFACTURING: {"name": "Advanced Manufacturing", "prerequisite": TECH_DEFENSE_INDUSTRY, "cost": 4.0, "facility": BUILDING_RESEARCH_LAB},
	TECH_AUTOMATION: {"name": "Automation", "prerequisite": TECH_ADVANCED_MANUFACTURING, "cost": 4.0, "facility": BUILDING_RESEARCH_LAB},
	TECH_AEROSPACE: {"name": "Aerospace", "prerequisite": TECH_AUTOMATION, "cost": 4.0, "facility": BUILDING_RESEARCH_LAB},
	TECH_NEAR_FUTURE: {"name": "Near Future Systems", "prerequisite": TECH_AEROSPACE, "cost": 5.0, "facility": BUILDING_RESEARCH_LAB},
}

const UNIT_DATA := {
	UNIT_INFANTRY: {"name": "Infantry", "facility": BUILDING_BARRACKS, "tech": TECH_NONE, "money": 10.0, "materials": 0.0, "fuel": 0.0, "supplies": 1.0, "workforce": 1, "power": 1.0, "ticks": 2},
	UNIT_TANK: {"name": "Tank", "facility": BUILDING_VEHICLE_FACTORY, "tech": TECH_ADVANCED_MANUFACTURING, "money": 30.0, "materials": 5.0, "fuel": 2.0, "supplies": 2.0, "workforce": 1, "power": 3.0, "ticks": 3},
	UNIT_ARTILLERY: {"name": "Artillery", "facility": BUILDING_VEHICLE_FACTORY, "tech": TECH_ADVANCED_MANUFACTURING, "money": 25.0, "materials": 4.0, "fuel": 1.0, "supplies": 2.0, "workforce": 1, "power": 3.0, "ticks": 3},
	UNIT_ROBOT: {"name": "Robot Unit", "facility": BUILDING_DRONE_FACTORY, "tech": TECH_AUTOMATION, "money": 40.0, "materials": 6.0, "fuel": 0.0, "supplies": 4.0, "workforce": 0, "power": 4.0, "ticks": 4},
	UNIT_RECON_DRONE: {"name": "Recon Drone", "facility": BUILDING_DRONE_FACTORY, "tech": TECH_AUTOMATION, "money": 15.0, "materials": 2.0, "fuel": 0.0, "supplies": 1.0, "workforce": 0, "power": 2.0, "ticks": 2},
	UNIT_BOMBER: {"name": "Bomber", "facility": BUILDING_AIRBASE, "tech": TECH_AEROSPACE, "money": 50.0, "materials": 8.0, "fuel": 4.0, "supplies": 4.0, "workforce": 2, "power": 4.0, "ticks": 4},
	UNIT_FIGHTER: {"name": "Fighter", "facility": BUILDING_AIRBASE, "tech": TECH_AEROSPACE, "money": 45.0, "materials": 7.0, "fuel": 3.0, "supplies": 3.0, "workforce": 1, "power": 4.0, "ticks": 4},
}

const IMPORT_PRICES := {
	RESOURCE_FOOD: 1.0,
	RESOURCE_MATERIALS: 2.0,
	RESOURCE_FUEL: 2.0,
	RESOURCE_MILITARY_SUPPLIES: 3.0,
}
