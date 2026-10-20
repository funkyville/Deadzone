# Obstacle.gd
# Static obstacles moving downward (cars, barriers)
# Attach to Area2D or StaticBody2D with CollisionShape2D

extends Area2D
class_name Obstacle

@export var fall_speed: float = 320.0
@export var damage_on_hit: int = 25
@export var destroy_on_hit: bool = false

func _ready():
	add_to_group("obstacle")
	body_entered.connect(_on_body_entered)
	# Optional random rotation for variety
	rotation_degrees = randf_range(-5, 5)

func _physics_process(delta):
	global_position.y += fall_speed * delta
	# Auto-recycle when off-screen (below player)
	if global_position.y > get_viewport_rect().size.y + 200:
		queue_free()

func _on_body_entered(body):
	if body is Player:
		body.take_damage(damage_on_hit)
		GameManager.camera_shake.emit(0.3, 8.0)
		if destroy_on_hit:
			queue_free()
		else:
			# Bounce feedback
			var tween = create_tween()
			tween.tween_property(self, "modulate", Color.RED, 0.1)
			tween.tween_property(self, "modulate", Color.WHITE, 0.2)
