# Main.gd
# Godot 4.x - Main scene controller (attach to Node2D root of Main.tscn)

extends Node2D

@onready var player: Player = $Player
@onready var spawner: Spawner = $Spawner
@onready var road: Node2D = $Road
@export var scroll_speed: float = 400.0

func _ready():
	GameManager.reset_run()
	# Connect player signals for tally
	player.health_changed.connect(func(c,m): GameManager.health = c)
	player.died.connect(func(): pass)
	# Road scroll illusion (move texture)
	if road and road is ParallaxBackground:
		pass

func _process(delta):
	# Scroll road texture to simulate forward motion
	if road and not GameManager.is_game_over:
		road.position.y += scroll_speed * delta
		if road.position.y > 600:
			road.position.y = 0
		GameManager.run_stats["distance"] = GameManager.run_stats.get("distance", 0) + scroll_speed * delta

func _input(event):
	if event.is_action_pressed("pause") and not GameManager.is_game_over:
		get_tree().paused = !get_tree().paused
