# BuildingData.gd — Resource definition for 3 building types
# Godot 4.x — GDScript

extends Resource
class_name BuildingData

enum Type { HEADQUARTERS, FARM, BARRACKS }

@export var type: Type
@export var display_name: String = "Headquarters"
@export var icon: Texture2D
@export var size: Vector2i = Vector2i(1,1) # grid cells occupied
@export var build_cost_food: int = 0
@export var build_cost_metal: int = 0
@export var build_cost_currency: int = 0

# Per-level upgrade definitions
# level 1 is built state, upgrading to level 2 costs upgrade_cost[1] etc.
@export var max_level: int = 5
@export var upgrade_cost_food: Array[int] = [0, 50, 120, 250, 400] # index = target level
@export var upgrade_cost_metal: Array[int] = [0, 30, 80, 180, 300]
@export var upgrade_time_sec: Array[float] = [0, 30, 60, 120, 240] # 30s for lvl2, etc.

# Resource generation per second at each level (Farm generates food, HQ generates storage bonus)
@export var gen_food_per_sec: Array[float] = [0, 0.5, 1.0, 1.8, 2.5] # Farm
@export var gen_metal_per_sec: Array[float] = [0, 0.2, 0.5, 0.9, 1.4] # Farm secondary
@export var defense_bonus: Array[int] = [0, 10, 25, 45, 70] # Barracks/HQ
@export var storage_bonus: Array[int] = [0, 100, 250, 500, 800] # HQ

static func make_hq() -> BuildingData:
	var d = BuildingData.new()
	d.type = Type.HEADQUARTERS
	d.display_name = "Headquarters"
	d.size = Vector2i(2,2)
	d.build_cost_food = 0; d.build_cost_metal = 0
	d.max_level = 5
	d.upgrade_cost_food = [0, 80, 150, 300, 500]
	d.upgrade_cost_metal = [0, 50, 100, 220, 400]
	d.upgrade_time_sec = [0, 30, 60, 120, 180]
	d.gen_food_per_sec = [0, 0, 0, 0, 0]
	d.storage_bonus = [0, 100, 250, 500, 900]
	return d

static func make_farm() -> BuildingData:
	var d = BuildingData.new()
	d.type = Type.FARM
	d.display_name = "Resource Farm"
	d.size = Vector2i(1,1)
	d.build_cost_food = 20; d.build_cost_metal = 10
	d.max_level = 5
	d.upgrade_cost_food = [0, 40, 90, 180, 350]
	d.upgrade_cost_metal = [0, 30, 70, 150, 280]
	d.upgrade_time_sec = [0, 30, 60, 90, 150]
	d.gen_food_per_sec = [0, 0.5, 1.0, 1.8, 3.0]
	d.gen_metal_per_sec = [0, 0.1, 0.25, 0.5, 0.9]
	return d

static func make_barracks() -> BuildingData:
	var d = BuildingData.new()
	d.type = Type.BARRACKS
	d.display_name = "Barracks"
	d.size = Vector2i(2,1)
	d.build_cost_food = 30; d.build_cost_metal = 40
	d.max_level = 5
	d.upgrade_cost_food = [0, 60, 130, 260, 420]
	d.upgrade_cost_metal = [0, 80, 160, 300, 500]
	d.upgrade_time_sec = [0, 30, 45, 90, 150]
	d.defense_bonus = [0, 15, 35, 60, 100]
	return d

func get_upgrade_cost(level: int) -> Dictionary:
	# level = current level, returns cost to go to level+1
	var target = level + 1
	if target > max_level:
		return {}
	return {"food": upgrade_cost_food[target] if target < upgrade_cost_food.size() else 9999,
			"metal": upgrade_cost_metal[target] if target < upgrade_cost_metal.size() else 9999,
			"time": upgrade_time_sec[target] if target < upgrade_time_sec.size() else 0}

func get_generation(level: int) -> Dictionary:
	return {"food": gen_food_per_sec[level] if level < gen_food_per_sec.size() else 0,
			"metal": gen_metal_per_sec[level] if level < gen_metal_per_sec.size() else 0}
