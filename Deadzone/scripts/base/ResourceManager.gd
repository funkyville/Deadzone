# ResourceManager.gd — Autoload singleton for resources + generation
# Project Settings → Autoload → ResourceManager.gd

extends Node

signal resources_updated(food: int, metal: int, hard_currency: int)
signal production_updated(food_per_sec: float, metal_per_sec: float)

var food: int = 200:
	set(v): food = max(0, v); resources_updated.emit(food, metal, hard_currency)
var metal: int = 150:
	set(v): metal = max(0, v); resources_updated.emit(food, metal, hard_currency)
var hard_currency: int = 10:
	set(v): hard_currency = max(0, v); resources_updated.emit(food, metal, hard_currency)

var food_per_sec: float = 0.0
var metal_per_sec: float = 0.0

var _tick_timer: Timer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tick_timer = Timer.new()
	_tick_timer.wait_time = 1.0
	_tick_timer.autostart = true
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)

func can_afford(need_food: int, need_metal: int) -> bool:
	return food >= need_food and metal >= need_metal

func spend(need_food: int, need_metal: int) -> bool:
	if not can_afford(need_food, need_metal):
		return false
	food -= need_food
	metal -= need_metal
	SaveManager.save_game()
	return true

func add_resources(add_food: int, add_metal: int):
	food += add_food
	metal += add_metal

func recalculate_generation():
	food_per_sec = 0.0
	metal_per_sec = 0.0
	var grid = get_tree().get_first_node_in_group("grid") as BaseGrid
	if not grid:
		return
	for b in grid.get_all_buildings():
		var gen = b.data.get_generation(b.level)
		food_per_sec += gen["food"]
		metal_per_sec += gen["metal"]
	production_updated.emit(food_per_sec, metal_per_sec)

func _on_tick():
	if food_per_sec > 0 or metal_per_sec > 0:
		# We add per second but keep ints via accumulating float remainder
		pass
	# Use float accumulator
	Accum.food_accum += food_per_sec
	Accum.metal_accum += metal_per_sec
	var add_food = int(Accum.food_accum)
	var add_metal = int(Accum.metal_accum)
	if add_food != 0:
		Accum.food_accum -= add_food
		food += add_food
	if add_metal != 0:
		Accum.metal_accum -= add_metal
		metal += add_metal

# Offline generation: called on load
func apply_offline_progress(seconds: float):
	if seconds <= 0:
		return
	recalculate_generation()
	var add_food = int(food_per_sec * seconds)
	var add_metal = int(metal_per_sec * seconds)
	if add_food > 0 or add_metal > 0:
		food += add_food
		metal += add_metal
		print("[ResourceManager] Offline progress: +%d food, +%d metal for %.0fs" % [add_food, add_metal, seconds])

# Helper accumulator for fractional resources
var Accum = { "food_accum": 0.0, "metal_accum": 0.0 }
