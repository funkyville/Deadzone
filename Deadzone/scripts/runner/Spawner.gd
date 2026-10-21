# Spawner.gd
# Godot 4.x - Random spawner for obstacles, zombies, barrels/gates
# Attach to Node2D or Marker2D at top of screen

extends Node2D
class_name Spawner

@export var enabled: bool = true

# PackedScenes - assign in Inspector
@export var zombie_scene: PackedScene
@export var obstacle_scene: PackedScene
@export var barrel_scene: PackedScene
@export var gate_scene: PackedScene

@export var spawn_interval_min: float = 0.5
@export var spawn_interval_max: float = 1.5
@export var difficulty_ramp: float = 0.02 # increase speed over time

# Lane positions (must match Player)
@export var lane_count: int = 3
@export var lane_distance: float = 120.0

var elapsed: float = 0.0
var next_spawn: float = 1.0

@onready var timer: Timer = $Timer

func _ready():
	add_to_group("spawner")
	_schedule_next()

func _schedule_next():
	var ramp = clamp(elapsed * difficulty_ramp, 0, 0.6)
	var min_t = max(0.25, spawn_interval_min - ramp)
	var max_t = max(0.5, spawn_interval_max - ramp)
	next_spawn = randf_range(min_t, max_t)

func _process(delta):
	if not enabled or GameManager.is_game_over:
		return
	elapsed += delta
	next_spawn -= delta
	if next_spawn <= 0:
		spawn_random()
		_schedule_next()

func lane_to_x(lane: int) -> float:
	var center_offset = (lane_count - 1) / 2.0
	return (lane - center_offset) * lane_distance

func random_lane() -> int:
	return randi() % lane_count

func spawn_random():
	var roll = randf()
	var lane = random_lane()
	var x = lane_to_x(lane)
	var y = global_position.y # top of screen (spawner at y = -100)

	if roll < 0.30:
		spawn_obstacle(x, y)
	elif roll < 0.65:
		spawn_zombie(x, y)
	elif roll < 0.85:
		spawn_barrel(x, y)
	else:
		spawn_gate(x, y)

func spawn_zombie(x: float, y: float):
	if zombie_scene == null:
		return
	var z = zombie_scene.instantiate()
	z.global_position = Vector2(x, y)
	z.fall_speed = randf_range(180, 280) + elapsed * 10.0
	get_tree().current_scene.add_child(z)

func spawn_obstacle(x: float, y: float):
	if obstacle_scene == null:
		return
	var o = obstacle_scene.instantiate()
	o.global_position = Vector2(x, y)
	o.fall_speed = randf_range(300, 380) + elapsed * 12.0
	get_tree().current_scene.add_child(o)

func spawn_barrel(x: float, y: float):
	if barrel_scene == null:
		return
	var b = barrel_scene.instantiate() as BarrelGate
	var loot = BarrelGate.random_loot()
	b.global_position = Vector2(x, y)
	b.buff_type = loot["buff_type"]
	b.buff_value = loot["buff_value"]
	b.label_text = loot["label"]
	b.max_hp = loot["hp"]
	if loot.has("duration"):
		b.buff_duration = loot["duration"]
	get_tree().current_scene.add_child(b)

func spawn_gate(x: float, y: float):
	if gate_scene == null:
		spawn_barrel(x, y)
		return
	var g = gate_scene.instantiate() as BarrelGate
	var loot = BarrelGate.random_loot()
	g.global_position = Vector2(x, y)
	g.type = BarrelGate.Type.GATE
	g.buff_type = loot["buff_type"]
	g.buff_value = loot["buff_value"]
	g.label_text = loot["label"]
	g.max_hp = int(loot["hp"] * 0.6) # gates easier to break
	if loot.has("duration"):
		g.buff_duration = loot["duration"]
	get_tree().current_scene.add_child(g)

# Called by GameManager to increase difficulty
func set_difficulty_multiplier(mult: float):
	spawn_interval_min = max(0.2, spawn_interval_min / mult)
