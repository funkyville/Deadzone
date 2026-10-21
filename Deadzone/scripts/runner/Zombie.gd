# Zombie.gd
# Godot 4.x - Enemy that moves toward player, takes damage, dies for score
# Attach to Area2D or CharacterBody2D with CollisionShape2D

extends Area2D
class_name Zombie

@export var max_health: int = 50
@export var fall_speed: float = 220.0
@export var sway_amplitude: float = 15.0
@export var sway_speed: float = 2.0
@export var damage_to_player: int = 20
@export var score_value: int = 10
@export var metal_drop: int = 5

var health: int
var base_x: float
var time: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var hp_bar: ProgressBar = $HPBar

func _ready():
	add_to_group("enemy")
	add_to_group("destructible")
	health = max_health
	base_x = global_position.x
	if hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = health
		hp_bar.visible = false
	body_entered.connect(_on_body_entered)
	if anim and anim.has_animation("walk"):
		anim.play("walk")

func _physics_process(delta):
	time += delta
	global_position.y += fall_speed * delta
	# Slight sway
	global_position.x = base_x + sin(time * sway_speed) * sway_amplitude
	if global_position.y > get_viewport_rect().size.y + 250:
		queue_free()

func take_damage(amount: int):
	health -= amount
	if hp_bar:
		hp_bar.visible = true
		hp_bar.value = health
	# Flash
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color.RED, 0.05)
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)
	if health <= 0:
		die()

func die():
	GameManager.add_score(score_value)
	GameManager.metal += metal_drop
	var player = get_tree().get_first_node_in_group("player") as Player
	if player:
		player.zombies_killed += 1
		player.add_score(score_value)
	# Death anim
	collision_layer = 0
	collision_mask = 0
	if anim and anim.has_animation("die"):
		anim.play("die")
		await anim.animation_finished
	GameManager.spawn_pickup(global_position, "metal", metal_drop)
	GameManager.show_floating_text(global_position, "+%d" % score_value, Color.YELLOW)
	queue_free()

func _on_body_entered(body):
	if body is Player:
		body.take_damage(damage_to_player)
		GameManager.camera_shake.emit(0.35, 10.0)
		queue_free()
