# BarrelGate.gd
# Godot 4.x - Destructible loot barrels / gates with numerical values
# Shows e.g. "+50 Ammo", "x2 Damage 5s", "+20 Food"
# Attach to Area2D with CollisionShape2D, Label, ProgressBar

extends Area2D
class_name BarrelGate

enum Type { BARREL, GATE }

@export var type: Type = Type.BARREL
@export var max_hp: int = 30
@export var buff_type: String = "ammo" # ammo, food, metal, damage_x, heal
@export var buff_value: float = 50.0
@export var buff_duration: float = 5.0 # for damage_x
@export var fall_speed: float = 200.0

@export var label_text: String = "+50 Ammo" # auto-generated if empty

var hp: int
@onready var label: Label = $Label
@onready var hp_bar: ProgressBar = $HPBar
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer

func _ready():
	add_to_group("destructible")
	hp = max_hp
	if label:
		if label_text == "":
			label_text = _auto_label()
		label.text = label_text
		_update_label_color()
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp
		hp_bar.visible = false
	body_entered.connect(_on_body_entered)

func _auto_label() -> String:
	match buff_type:
		"ammo": return "+%d Ammo" % int(buff_value)
		"food": return "+%d Food" % int(buff_value)
		"metal": return "+%d Metal" % int(buff_value)
		"damage_x": return "x%.1f Damage" % buff_value
		"heal": return "+%d HP" % int(buff_value)
		_: return "+%d" % int(buff_value)

func _update_label_color():
	if not label: return
	match buff_type:
		"ammo": label.modulate = Color.YELLOW
		"food": label.modulate = Color.GREEN
		"metal": label.modulate = Color.SLATE_GRAY
		"damage_x": label.modulate = Color.RED
		"heal": label.modulate = Color.CYAN

func _physics_process(delta):
	global_position.y += fall_speed * delta
	if global_position.y > get_viewport_rect().size.y + 200:
		queue_free()

func take_damage(amount: int):
	hp -= amount
	if hp_bar:
		hp_bar.visible = true
		hp_bar.value = hp
	if sprite:
		sprite.modulate = Color(1, 0.7, 0.7)
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)
	if hp <= 0:
		explode()

func explode():
	# Give buff to player
	var player = get_tree().get_first_node_in_group("player") as Player
	if player:
		player.apply_buff(buff_type, buff_value, buff_duration)
		player.barrels_destroyed += 1
		# Also add to global stats
		if buff_type == "metal":
			GameManager.metal += int(buff_value)
		elif buff_type == "food":
			GameManager.food += int(buff_value)
		elif buff_type == "ammo":
			GameManager.ammo += int(buff_value)
		GameManager.add_score(5)
	# VFX
	GameManager.spawn_explosion(global_position)
	if anim and anim.has_animation("explode"):
		anim.play("explode")
		await anim.animation_finished
	queue_free()

func _on_body_entered(body):
	if body is Player:
		# Gates: player passes through, auto-collect without shooting if gate is low HP gate?
		# For barrels, we make them solid - damage player slightly
		if type == Type.GATE:
			explode()
		else:
			body.take_damage(10)
			GameManager.camera_shake.emit(0.2, 6.0)

# Helper to randomize loot (called by Spawner)
static func random_loot() -> Dictionary:
	var pool = [
		{"buff_type":"ammo", "buff_value":50, "label":"+50 Ammo", "hp":30},
		{"buff_type":"metal", "buff_value":20, "label":"+20 Metal", "hp":25},
		{"buff_type":"food", "buff_value":15, "label":"+15 Food", "hp":25},
		{"buff_type":"damage_x", "buff_value":2.0, "label":"x2 Damage", "hp":40, "duration":5.0},
		{"buff_type":"heal", "buff_value":25, "label":"+25 HP", "hp":30},
		{"buff_type":"ammo", "buff_value":100, "label":"+100 Ammo", "hp":45},
	]
	return pool.pick_random()
