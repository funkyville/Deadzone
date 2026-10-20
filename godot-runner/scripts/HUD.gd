# HUD.gd
# Godot 4.x - Heads Up Display + Game Over + Results Screen
# Attach to CanvasLayer

extends CanvasLayer

@onready var health_bar: ProgressBar = $TopBar/HealthBar
@onready var health_label: Label = $TopBar/HealthBar/Label
@onready var ammo_label: Label = $TopBar/AmmoLabel
@onready var metal_label: Label = $TopBar/MetalLabel
@onready var food_label: Label = $TopBar/FoodLabel
@onready var score_label: Label = $TopBar/ScoreLabel
@onready var damage_indicator: Label = $DamageBuffIndicator

@onready var game_over_panel: Panel = $GameOverPanel
@onready var results_score: Label = $GameOverPanel/VBox/Score
@onready var results_zombies: Label = $GameOverPanel/VBox/Zombies
@onready var results_barrels: Label = $GameOverPanel/VBox/Barrels
@onready var results_metal: Label = $GameOverPanel/VBox/Metal
@onready var results_food: Label = $GameOverPanel/VBox/Food
@onready var results_time: Label = $GameOverPanel/VBox/Time
@onready var restart_btn: Button = $GameOverPanel/VBox/RestartBtn
@onready var menu_btn: Button = $GameOverPanel/VBox/MenuBtn

@onready var camera: Camera2D = get_viewport().get_camera_2d()

func _ready():
	game_over_panel.visible = false
	restart_btn.pressed.connect(_on_restart)
	menu_btn.pressed.connect(_on_menu)
	GameManager.score_changed.connect(_on_score)
	GameManager.resources_changed.connect(_on_resources)
	GameManager.health_changed.connect(_on_health)
	GameManager.game_over_triggered.connect(_on_game_over)
	GameManager.floating_text_requested.connect(_spawn_floating_text)
	GameManager.camera_shake.connect(_shake)
	# Initial
	_on_health(GameManager.health, 100)
	_on_score(GameManager.score)
	_on_resources(GameManager.food, GameManager.metal, GameManager.ammo, GameManager.hard_currency)

func _on_health(current: int, max_val: int):
	if health_bar:
		health_bar.max_value = max_val
		health_bar.value = current
		health_label.text = "%d/%d HP" % [current, max_val]
		health_bar.tint_progress = Color.RED if current < 30 else Color.GREEN

func _on_score(s: int):
	score_label.text = "Score: %d" % s

func _on_resources(food: int, metal: int, ammo: int, hard_currency: int):
	ammo_label.text = "Ammo: %d" % ammo
	metal_label.text = "Metal: %d" % metal
	food_label.text = "Food: %d" % food

func _on_game_over():
	game_over_panel.visible = true
	results_score.text = "Score: %d (Best: %d)" % [GameManager.score, GameManager.high_score]
	results_zombies.text = "Zombies Killed: %d" % GameManager.run_stats.get("zombies_killed", 0)
	results_barrels.text = "Barrels Broken: %d" % GameManager.run_stats.get("barrels_destroyed", 0)
	results_metal.text = "Metal Collected: %d" % GameManager.metal
	results_food.text = "Food Collected: %d" % GameManager.food
	results_time.text = "Survived: %.1fs" % GameManager.run_stats.get("elapsed", 0)
	# Animate in
	game_over_panel.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.4)
	tween.tween_property(game_over_panel, "scale", Vector2(1.02, 1.02), 0.15)
	tween.tween_property(game_over_panel, "scale", Vector2(1, 1), 0.15)

func _on_restart():
	GameManager.restart()

func _on_menu():
	GameManager.go_to_menu()

func _spawn_floating_text(pos: Vector2, text: String, color: Color):
	var lbl = Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.z_index = 100
	# Convert world to screen (CanvasLayer is screen-space, so we approx)
	lbl.global_position = pos + Vector2(randf_range(-20, 20), -30)
	lbl.add_theme_font_size_override("font_size", 18)
	add_child(lbl)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 60, 0.8).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tween.finished.connect(func(): if is_instance_valid(lbl): lbl.queue_free())

func _shake(duration: float, strength: float):
	if camera == null:
		camera = get_viewport().get_camera_2d()
		if camera == null: return
	var orig_offset = camera.offset
	var tween = create_tween()
	for i in range(int(duration * 60)):
		var offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(camera, "offset", offset, 0.01)
	tween.tween_property(camera, "offset", orig_offset, 0.05)
