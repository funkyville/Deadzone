# Player.gd
# Godot 4.x - Vertical 3-Lane Runner Player
# Attach to CharacterBody2D with CollisionShape2D + Sprite2D + AnimationPlayer
# Handles: lane switching (touch/swipe + arrow keys), shooting, health, buffs

extends CharacterBody2D
class_name Player

signal lane_changed(new_lane: int)
signal shot_fired(bullet: Bullet)
signal health_changed(current: int, max: int)
signal died

# --- LANE SYSTEM ---
@export var lane_count: int = 3
@export var lane_distance: float = 120.0  # pixels between lanes
@export var lane_switch_duration: float = 0.18 # seconds (smooth tween)
@export var start_lane: int = 1 # 0=left,1=middle,2=right

var current_lane: int = 1
var target_x: float = 0.0
var is_switching: bool = false
var can_move: bool = true

# --- STATS ---
@export var max_health: int = 100
@export var base_damage: int = 25
@export var shoot_cooldown: float = 0.25
var health: int
var current_damage: int
var damage_buff_timer: float = 0.0
var damage_buff_multiplier: float = 1.0

# --- RESOURCES (synced to backend later) ---
var ammo: int = 100
var metal: int = 0
var food: int = 0
var score: int = 0
var barrels_destroyed: int = 0
var zombies_killed: int = 0

# --- SHOOTING ---
@export var bullet_scene: PackedScene
var can_shoot: bool = true
@onready var shoot_timer: Timer = $ShootTimer
@onready var muzzle: Marker2D = $Muzzle
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer

# --- TOUCH ---
var touch_start_x: float = 0.0
var swipe_threshold: float = 40.0

func _ready():
	health = max_health
	current_damage = base_damage
	current_lane = clamp(start_lane, 0, lane_count - 1)
	target_x = _lane_to_x(current_lane)
	global_position.x = target_x
	shoot_timer.wait_time = shoot_cooldown
	shoot_timer.one_shot = true
	shoot_timer.timeout.connect(_on_shoot_cooldown)
	add_to_group("player")

func _lane_to_x(lane: int) -> float:
	# Lanes centered at 0: [-lane_distance, 0, +lane_distance]
	var center_offset = (lane_count - 1) / 2.0
	return (lane - center_offset) * lane_distance

func _unhandled_input(event):
	if not can_move:
		return
	# Keyboard
	if event.is_action_pressed("move_left"):
		try_switch_lane(-1)
	elif event.is_action_pressed("move_right"):
		try_switch_lane(1)
	elif event.is_action_pressed("shoot"):
		shoot()
	# Touch / Mouse swipe
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start_x = event.position.x
		else:
			var delta = event.position.x - touch_start_x
			if delta < -swipe_threshold:
				try_switch_lane(-1)
			elif delta > swipe_threshold:
				try_switch_lane(1)
	if event is InputEventScreenDrag:
		pass # we use touch release above for crisp swipe
	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		# Tap left/right half to switch (mobile fallback)
		var half = get_viewport_rect().size.x / 2.0
		if event.position.x < half - 80:
			try_switch_lane(-1)
		elif event.position.x > half + 80:
			try_switch_lane(1)

func try_switch_lane(dir: int):
	if is_switching:
		return
	var new_lane = clamp(current_lane + dir, 0, lane_count - 1)
	if new_lane == current_lane:
		return
	current_lane = new_lane
	target_x = _lane_to_x(current_lane)
	_switch_with_tween(target_x)
	lane_changed.emit(current_lane)

func _switch_with_tween(to_x: float):
	is_switching = true
	# Smooth tween + slight lean animation
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position:x", to_x, lane_switch_duration)
	tween.finished.connect(func(): is_switching = false)
	# Visual lean
	if anim:
		anim.play("lean_" + ("left" if to_x < global_position.x else "right"))
		tween.finished.connect(func(): if anim.has_animation("idle"): anim.play("idle"))

func _process(delta):
	# Buff timer
	if damage_buff_timer > 0:
		damage_buff_timer -= delta
		if damage_buff_timer <= 0:
			_clear_damage_buff()

func shoot():
	if not can_shoot or ammo <= 0:
		# Optional: play empty click
		return
	if bullet_scene == null:
		push_warning("Player: bullet_scene not assigned - creating default bullet")
		return
	can_shoot = false
	ammo -= 1
	GameManager.ammo = ammo  # sync to global
	var bullet = bullet_scene.instantiate() as Bullet
	bullet.global_position = muzzle.global_position if muzzle else global_position + Vector2(0, -40)
	bullet.damage = int(current_damage * damage_buff_multiplier)
	bullet.lane = current_lane
	get_tree().current_scene.add_child(bullet)
	shot_fired.emit(bullet)
	shoot_timer.start()
	if anim and anim.has_animation("shoot"):
		anim.play("shoot")

func _on_shoot_cooldown():
	can_shoot = true

func take_damage(amount: int):
	if health <= 0:
		return
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	GameManager.health = health
	if anim and anim.has_animation("hit"):
		anim.play("hit")
	# Camera shake via GameManager
	GameManager.camera_shake.emit(0.2, 5.0)
	if health <= 0:
		die()

func die():
	can_move = false
	died.emit()
	GameManager.trigger_game_over()

# --- BUFFS FROM BARRELS/GATES ---
func apply_buff(buff_type: String, value: float, duration: float):
	match buff_type:
		"ammo":
			ammo += int(value)
			GameManager.ammo = ammo
			GameManager.show_floating_text(global_position, "+%d Ammo" % int(value), Color.YELLOW)
		"food":
			food += int(value)
			GameManager.food = food
			GameManager.show_floating_text(global_position, "+%d Food" % int(value), Color.GREEN)
		"metal":
			metal += int(value)
			GameManager.metal = metal
			GameManager.show_floating_text(global_position, "+%d Metal" % int(value), Color.GRAY)
		"damage_x":
			damage_buff_multiplier = value
			damage_buff_timer = duration
			current_damage = int(base_damage * damage_buff_multiplier)
			GameManager.show_floating_text(global_position, "x%.1f Damage %ds!" % [value, int(duration)], Color.RED)
			# Visual tint
			if sprite:
				sprite.modulate = Color(1, 0.5, 0.5)
		"heal":
			health = mini(max_health, health + int(value))
			health_changed.emit(health, max_health)
			GameManager.health = health
			GameManager.show_floating_text(global_position, "+%d HP" % int(value), Color.CYAN)
		_:
			push_warning("Unknown buff: " + buff_type)

func _clear_damage_buff():
	damage_buff_multiplier = 1.0
	current_damage = base_damage
	if sprite:
		sprite.modulate = Color.WHITE
	GameManager.show_floating_text(global_position, "Buff ended", Color.WHITE)

# Called by GameManager when collecting loose resources
func add_score(amount: int):
	score += amount
	GameManager.score = score
