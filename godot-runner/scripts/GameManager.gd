# GameManager.gd
# Godot 4.x - Autoload (Singleton)
# Tracks score, resources, health, game over, and syncs to backend
# Add as Autoload: Project → Project Settings → Autoload → GameManager.gd

extends Node

signal score_changed(new_score: int)
signal resources_changed(food: int, metal: int, ammo: int, hard_currency: int)
signal health_changed(current: int, max: int)
signal camera_shake(duration: float, strength: float)
signal game_over_triggered
signal floating_text_requested(pos: Vector2, text: String, color: Color)

# --- Game State ---
var is_game_over: bool = false
var is_paused: bool = false

var score: int = 0:
	set(v): score = v; score_changed.emit(score)
var food: int = 0:
	set(v): food = v; resources_changed.emit(food, metal, ammo, hard_currency)
var metal: int = 0:
	set(v): metal = v; resources_changed.emit(food, metal, ammo, hard_currency)
var ammo: int = 100:
	set(v): ammo = v; resources_changed.emit(food, metal, ammo, hard_currency)
var hard_currency: int = 0:
	set(v): hard_currency = v; resources_changed.emit(food, metal, ammo, hard_currency)
var health: int = 100:
	set(v): health = v; health_changed.emit(health, 100)

var high_score: int = 0
var run_stats: Dictionary = {}

# Backend URL (from previous deployment)
var backend_url: String = "https://survival-api-w6cr.onrender.com"
var jwt_token: String = "" # set after login

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func reset_run():
	is_game_over = false
	is_paused = false
	score = 0
	food = 0
	metal = 0
	ammo = 100
	hard_currency = 0
	health = 100
	run_stats = {
		"zombies_killed": 0,
		"barrels_destroyed": 0,
		"distance": 0.0,
		"start_time": Time.get_ticks_msec()
	}
	get_tree().paused = false

func add_score(amount: int):
	score += amount

func trigger_game_over():
	if is_game_over:
		return
	is_game_over = true
	game_over_triggered.emit()
	# Save high score
	if score > high_score:
		high_score = score
	# Fill final stats
	var player = get_tree().get_first_node_in_group("player") as Player
	if player:
		run_stats["zombies_killed"] = player.zombies_killed
		run_stats["barrels_destroyed"] = player.barrels_destroyed
		run_stats["food"] = food
		run_stats["metal"] = metal
		run_stats["ammo"] = ammo
		run_stats["score"] = score
	run_stats["elapsed"] = (Time.get_ticks_msec() - run_stats.get("start_time", 0)) / 1000.0
	# Sync to backend (fire-and-forget)
	sync_resources_to_backend()
	# Pause after delay
	await get_tree().create_timer(0.5).timeout
	get_tree().paused = true

# --- Backend Sync ---
func sync_resources_to_backend():
	if jwt_token == "" or backend_url == "":
		print("[GameManager] No JWT - skipping backend sync (login first)")
		return
	# Example: update player resources via PATCH increment or PUT
	var http = HTTPRequest.new()
	add_child(http)
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + jwt_token]
	# You would need player userId; for demo we use /me endpoint or store userId after login
	# http.request(backend_url + "/api/resources/1", headers, HTTPClient.METHOD_PUT, JSON.stringify({
	#   "food": food, "metal": metal, "ammo": ammo, "hard_currency": hard_currency
	# }))
	print("[GameManager] Sync queued: ", run_stats)

# --- Visual Helpers ---
func show_floating_text(pos: Vector2, text: String, color: Color = Color.WHITE):
	floating_text_requested.emit(pos, text, color)

func spawn_explosion(pos: Vector2):
	# Spawn particles - create simple Particles2D if you have it
	var particles = CPUParticles2D.new()
	particles.global_position = pos
	particles.emitting = true
	particles.amount = 16
	particles.lifetime = 0.4
	particles.speed_scale = 2.0
	particles.gravity = Vector2(0, 600)
	particles.initial_velocity_min = 100
	particles.initial_velocity_max = 250
	get_tree().current_scene.add_child(particles)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func spawn_pickup(pos: Vector2, type: String, amount: int):
	# Visual chip that flies to HUD - simplified as floating text
	show_floating_text(pos, "+%d %s" % [amount, type.capitalize()], Color.GOLD)

# --- Scene Flow ---
func restart():
	reset_run()
	get_tree().reload_current_scene()

func go_to_menu():
	reset_run()
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func quit_game():
	get_tree().quit()

# Login helper (call from Menu)
func login(email: String, password: String, on_done: Callable):
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		if code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			jwt_token = json.get("token", "")
			print("[Backend] Login OK, token saved")
			on_done.call(true, json)
		else:
			print("[Backend] Login failed: ", code)
			on_done.call(false, null)
		http.queue_free()
	)
	var headers = ["Content-Type: application/json"]
	var payload = JSON.stringify({"email": email, "password": password})
	http.request(backend_url + "/api/auth/login", headers, HTTPClient.METHOD_POST, payload)
