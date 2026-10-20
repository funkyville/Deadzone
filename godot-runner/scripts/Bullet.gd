# Bullet.gd
# Godot 4.x - Player projectile
# Attach to Area2D with CollisionShape2D + Sprite2D

extends Area2D
class_name Bullet

@export var speed: float = 900.0
@export var damage: int = 25
var lane: int = 1

@onready var sprite: Sprite2D = $Sprite2D

func _ready():
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	# Auto-despawn off-screen
	var notifier = VisibleOnScreenNotifier2D.new()
	add_child(notifier)
	notifier.screen_exited.connect(queue_free)
	# Safety timeout
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree():
		queue_free()

func _physics_process(delta):
	global_position.y -= speed * delta

func _on_area_entered(area):
	if area.is_in_group("destructible"):
		area.take_damage(damage)
		queue_free()
	if area.is_in_group("enemy"):
		area.take_damage(damage)
		queue_free()

func _on_body_entered(body):
	if body.is_in_group("enemy"):
		body.take_damage(damage)
		queue_free()
