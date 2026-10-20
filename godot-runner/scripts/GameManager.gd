# GameManager.gd
# Godot 4.x - Autoload (Singleton) — wired to survival-api-w6cr.onrender.com
# Tracks score/resources/health/game over + auto-login + cloud sync
# Add as Autoload: Project Settings → Autoload → GameManager.gd

extends Node

signal score_changed(new_score: int)
signal resources_changed(food: int, metal: int, ammo: int, hard_currency: int)
signal health_changed(current: int, max: int)
signal camera_shake(duration: float, strength: float)
signal game_over_triggered
signal floating_text_requested(pos: Vector2, text: String, color: Color)
signal auth_changed(logged_in: bool, username: String)
signal sync_status_changed(status: String) # offline, syncing, synced, failed

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

# --- Backend ---
var backend_url: String = "https://survival-api-w6cr.onrender.com"
var jwt_token: String = ""
var current_user: Dictionary = {}
var current_user_id: int = 0
var sync_status: String = "offline":
	set(v): sync_status = v; sync_status_changed.emit(v)
const AUTH_SAVE_PATH := "user://deadzone_auth.json"

# Session sync timer
var _session_timer: Timer = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_auth()
	# Auto-verify if we have a token
	if jwt_token != "" and _is_token_valid(jwt_token):
		verify_token(func(ok, _data):
			if ok:
				print("[GameManager] Auto-login OK as ", current_user.get("username","?"))
				sync_status = "synced"
				auth_changed.emit(true, current_user.get("username",""))
			else:
				print("[GameManager] Token expired, need login")
				sync_status = "offline"
		)
	else:
		if jwt_token != "":
			print("[GameManager] Expired token cleared")
			logout()
		sync_status = "offline"

func reset_run():
	is_game_over = false
	is_paused = false
	score = 0
	food = 0
	metal = 0
	# Keep ammo from server if logged in, else reset
	if jwt_token == "":
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
	_start_session_sync()

func add_score(amount: int):
	score += amount

func trigger_game_over():
	if is_game_over:
		return
	is_game_over = true
	_stop_session_sync()
	game_over_triggered.emit()
	if score > high_score:
		high_score = score
	var player = get_tree().get_first_node_in_group("player") as Player
	if player:
		run_stats["zombies_killed"] = player.zombies_killed
		run_stats["barrels_destroyed"] = player.barrels_destroyed
		run_stats["food"] = food
		run_stats["metal"] = metal
		run_stats["ammo"] = ammo
		run_stats["score"] = score
	run_stats["elapsed"] = (Time.get_ticks_msec() - run_stats.get("start_time", 0)) / 1000.0
	# Sync resources + final session
	sync_resources_to_backend(func(ok, _r): 
		if ok:
			print("[GameManager] Sync OK")
			sync_status = "synced"
		else:
			sync_status = "failed"
	)
	sync_session_state("offline")
	await get_tree().create_timer(0.5).timeout
	get_tree().paused = true

# --- Auth Persistence ---
func _save_auth():
	var file = FileAccess.open(AUTH_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"token": jwt_token, "user": current_user}))
		print("[Auth] Saved to ", AUTH_SAVE_PATH)

func _load_auth():
	if not FileAccess.file_exists(AUTH_SAVE_PATH):
		return
	var file = FileAccess.open(AUTH_SAVE_PATH, FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		if json:
			jwt_token = json.get("token","")
			current_user = json.get("user",{})
			current_user_id = int(current_user.get("id", _decode_jwt(jwt_token).get("id",0)))
			if current_user_id != 0:
				print("[Auth] Loaded token for user ", current_user_id)

func _decode_jwt(token: String) -> Dictionary:
	var parts = token.split(".")
	if parts.size() < 2:
		return {}
	var payload = parts[1]
	# Pad base64
	while payload.length() % 4 != 0:
		payload += "="
	payload = payload.replace("-", "+").replace("_", "/")
	var decoded = Marshalls.base64_to_utf8(payload)
	if decoded == "":
		return {}
	var json = JSON.parse_string(decoded)
	return json if json is Dictionary else {}

func _is_token_valid(token: String) -> bool:
	var payload = _decode_jwt(token)
	if payload.is_empty() or not payload.has("exp"):
		return false
	var exp = int(payload["exp"])
	var now = int(Time.get_unix_time_from_system())
	return exp > now

# --- Backend Auth ---
func login(email: String, password: String, on_done: Callable):
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		if code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			jwt_token = json.get("token","")
			current_user = json.get("user",{})
			current_user_id = int(current_user.get("id",0))
			_save_auth()
			auth_changed.emit(true, current_user.get("username",""))
			sync_status = "synced"
			print("[Backend] Login OK ", current_user)
			on_done.call(true, json)
		else:
			print("[Backend] Login failed ", code, " ", body.get_string_from_utf8())
			on_done.call(false, null)
		http.queue_free()
	, CONNECT_ONE_SHOT)
	var headers = ["Content-Type: application/json"]
	var payload = JSON.stringify({"email": email, "password": password})
	http.request(backend_url + "/api/auth/login", headers, HTTPClient.METHOD_POST, payload)

func register_user(username: String, email: String, password: String, continent_id: int, on_done: Callable):
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		if code == 201:
			var json = JSON.parse_string(body.get_string_from_utf8())
			jwt_token = json.get("token","")
			current_user = json.get("user",{})
			current_user_id = int(current_user.get("id",0))
			_save_auth()
			auth_changed.emit(true, current_user.get("username",""))
			sync_status = "synced"
			print("[Backend] Register OK ", current_user)
			on_done.call(true, json)
		else:
			print("[Backend] Register failed ", code, " ", body.get_string_from_utf8())
			on_done.call(false, null)
		http.queue_free()
	, CONNECT_ONE_SHOT)
	var headers = ["Content-Type: application/json"]
	var payload = JSON.stringify({"username": username, "email": email, "password": password, "continent_id": continent_id})
	http.request(backend_url + "/api/auth/register", headers, HTTPClient.METHOD_POST, payload)

func verify_token(on_done: Callable):
	if jwt_token == "":
		on_done.call(false, null)
		return
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		if code == 200:
			var json = JSON.parse_string(body.get_string_from_utf8())
			current_user = json.get("user", current_user)
			current_user_id = int(current_user.get("id", current_user_id))
			_save_auth()
			on_done.call(true, json)
		else:
			print("[Backend] Verify failed ", code)
			# Don't clear token automatically - let caller decide
			on_done.call(false, null)
		http.queue_free()
	, CONNECT_ONE_SHOT)
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + jwt_token]
	http.request(backend_url + "/api/auth/verify", headers, HTTPClient.METHOD_GET, "")

func logout():
	jwt_token = ""
	current_user = {}
	current_user_id = 0
	sync_status = "offline"
	auth_changed.emit(false, "")
	if FileAccess.file_exists(AUTH_SAVE_PATH):
		DirAccess.remove_absolute(AUTH_SAVE_PATH)
	print("[Auth] Logged out")

# --- Backend Sync ---
func sync_resources_to_backend(on_done: Callable = Callable()):
	if jwt_token == "" or backend_url == "" or current_user_id == 0:
		print("[GameManager] No auth - skipping sync")
		if on_done.is_valid():
			on_done.call(false, {"message": "Not logged in"})
		return
	sync_status = "syncing"
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		var ok = (code == 200)
		if ok:
			print("[GameManager] Resources synced: food=", food, " metal=", metal, " ammo=", ammo)
		else:
			print("[GameManager] Sync failed ", code, " ", body.get_string_from_utf8())
		if on_done.is_valid():
			on_done.call(ok, JSON.parse_string(body.get_string_from_utf8()))
		http.queue_free()
	, CONNECT_ONE_SHOT)
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + jwt_token]
	var payload = JSON.stringify({"food": food, "metal": metal, "ammo": ammo, "hard_currency": hard_currency})
	http.request(backend_url + "/api/resources/" + str(current_user_id), headers, HTTPClient.METHOD_PUT, payload)

func sync_session_state(status: String = "online", extra: Dictionary = {}):
	if jwt_token == "" or current_user_id == 0:
		return
	var player = get_tree().get_first_node_in_group("player") as Player
	var x_pos = int(player.global_position.x) if player else 0
	var y_pos = int(player.global_position.y) if player else 0
	var zone = extra.get("zone", "wasteland")
	var lane_name = ["Left","Center","Right"][player.current_lane] if player else "Center"
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r,_c,_h,_b): http.queue_free(), CONNECT_ONE_SHOT)
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + jwt_token]
	# Try POST first, fallback to PUT coordinates
	var payload = JSON.stringify({
		"x": x_pos, "y": y_pos, "zone": zone + "_" + lane_name,
		"status": status, "health": health
	})
	# POST /api/session creates/updates
	http.request(backend_url + "/api/session", headers, HTTPClient.METHOD_POST, payload)

func _start_session_sync():
	if _session_timer and is_instance_valid(_session_timer):
		_session_timer.queue_free()
	_session_timer = Timer.new()
	_session_timer.wait_time = 3.0
	_session_timer.autostart = true
	_session_timer.timeout.connect(func(): sync_session_state("online"))
	add_child(_session_timer)

func _stop_session_sync():
	if _session_timer and is_instance_valid(_session_timer):
		_session_timer.stop()
		_session_timer.queue_free()
		_session_timer = null
	sync_session_state("offline")

# --- Visual Helpers ---
func show_floating_text(pos: Vector2, text: String, color: Color = Color.WHITE):
	floating_text_requested.emit(pos, text, color)

func spawn_explosion(pos: Vector2):
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
	show_floating_text(pos, "+%d %s" % [amount, type.capitalize()], Color.GOLD)

# --- Scene Flow ---
func restart():
	reset_run()
	get_tree().reload_current_scene()

func go_to_menu():
	reset_run()
	_stop_session_sync()
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")

func quit_game():
	get_tree().quit()
