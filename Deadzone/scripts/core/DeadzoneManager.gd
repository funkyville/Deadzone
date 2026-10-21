# DeadzoneManager.gd — Unified Autoload for Deadzone (Base + Runner)
# Godot 4.x — This is the single source of truth, do not separate again
# Manages: resources, save, auth, scene flow between Base and Runner

extends Node

signal resources_changed(food:int, metal:int, ammo:int, hard_currency:int)
signal production_changed(food_ps:float, metal_ps:float)
signal auth_changed(logged_in:bool, username:String)
signal sync_status_changed(status:String)

# --- Resources (shared across Base and Runner) ---
var food: int = 200:
	set(v): food = max(0,v); resources_changed.emit(food, metal, ammo, hard_currency)
var metal: int = 150:
	set(v): metal = max(0,v); resources_changed.emit(food, metal, ammo, hard_currency)
var ammo: int = 100:
	set(v): ammo = max(0,v); resources_changed.emit(food, metal, ammo, hard_currency)
var hard_currency: int = 10:
	set(v): hard_currency = max(0,v); resources_changed.emit(food, metal, ammo, hard_currency)
var health: int = 100

# Generation (from Farm levels)
var food_per_sec: float = 0.0
var metal_per_sec: float = 0.0
var accum_food: float = 0.0
var accum_metal: float = 0.0

# Backend
var backend_url: String = "https://survival-api-w6cr.onrender.com"
var jwt_token: String = ""
var current_user: Dictionary = {}
var current_user_id: int = 0
var sync_status: String = "offline":
	set(v): sync_status=v; sync_status_changed.emit(v)

# Run stats (runner → base)
var last_run: Dictionary = {}

const SAVE_PATH := "user://deadzone_save.json"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_auth()
	_load_save() # also handles offline generation & upgrades
	# Tick for generation
	var t = Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)

# --- Scene Flow (ONE PROJECT) ---
func go_menu(): get_tree().change_scene_to_file("res://scenes/Menu.tscn")
func go_base():
	save_game()
	get_tree().change_scene_to_file("res://scenes/Base.tscn")
func go_runner():
	# Save before leaving base so runner starts with current resources
	save_game()
	get_tree().change_scene_to_file("res://scenes/Runner.tscn")
func on_runner_finished(run_result: Dictionary):
	# Called from Runner's Game Over
	last_run = run_result
	# Merge runner loot into base resources
	food += int(run_result.get("food",0))
	metal += int(run_result.get("metal",0))
	ammo = int(run_result.get("ammo", ammo)) # runner consumes ammo
	health = 100 # reset for next run
	save_game()
	sync_to_backend()

func can_afford(f:int, m:int) -> bool: return food >= f and metal >= m
func spend(f:int, m:int) -> bool:
	if not can_afford(f,m): return false
	food -= f; metal -= m; save_game(); return true

func add_resources(f:int, m:int):
	food += f; metal += m

func recalc_generation():
	food_per_sec = 0; metal_per_sec = 0
	var grid = get_tree().get_first_node_in_group("grid")
	if not grid: return
	for b in grid.get_all_buildings():
		var gen = b.data.get_generation(b.level)
		food_per_sec += gen["food"]
		metal_per_sec += gen["metal"]
	production_changed.emit(food_per_sec, metal_per_sec)

func _tick():
	if food_per_sec==0 and metal_per_sec==0: return
	accum_food += food_per_sec
	accum_metal += metal_per_sec
	var add_f = int(accum_food); var add_m = int(accum_metal)
	if add_f: accum_food -= add_f; food += add_f
	if add_m: accum_metal -= add_m; metal += add_m

func apply_offline(seconds:float):
	if seconds<=0: return
	var add_f = int(food_per_sec * seconds)
	var add_m = int(metal_per_sec * seconds)
	if add_f or add_m:
		food += add_f; metal += add_m
		print("[Deadzone] Offline +%d food +%d metal for %.0fs" % [add_f, add_m, seconds])

# --- Persistence (ONE FILE, includes both segments) ---
func save_game():
	var data = {
		"last_save_unix": int(Time.get_unix_time_from_system()),
		"resources": {"food":food, "metal":metal, "ammo":ammo, "hard_currency":hard_currency},
		"last_run": last_run,
		"buildings": []
	}
	var grid = get_tree().get_first_node_in_group("grid")
	if grid:
		for b in grid.get_all_buildings():
			data["buildings"].append(b.to_save_dict())
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data,"\t"))

func _load_save():
	if not FileAccess.file_exists(SAVE_PATH):
		print("[Deadzone] No save, fresh base")
		return
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json = JSON.parse_string(f.get_as_text())
	if not json: return
	var res = json.get("resources",{})
	food = int(res.get("food",200)); metal = int(res.get("metal",150)); ammo = int(res.get("ammo",100)); hard_currency = int(res.get("hard_currency",10))
	last_run = json.get("last_run",{})
	var saved = int(json.get("last_save_unix", int(Time.get_unix_time_from_system())))
	var now = int(Time.get_unix_time_from_system())
	var offline = now - saved
	print("[Deadzone] Offline ", offline, "s")
	# Buildings will be added by Base scene after it's ready — we store pending list
	_pending_buildings = json.get("buildings", [])
	_pending_offline = offline
	# Don't apply generation yet — wait for grid to exist, then Base will call apply_pending()

var _pending_buildings: Array = []
var _pending_offline: float = 0

func apply_pending_to_grid(grid: Node):
	if _pending_buildings.is_empty(): return
	for bd in _pending_buildings:
		var b = Building.from_save_dict(bd)
		grid.add_existing_building(b)
		b.check_offline_completion(int(Time.get_unix_time_from_system()))
	_pending_buildings.clear()
	recalc_generation()
	apply_offline(_pending_offline)
	save_game()

# --- Auth (shared) ---
func _save_auth():
	var fa = FileAccess.open("user://deadzone_auth.json", FileAccess.WRITE)
	if fa: fa.store_string(JSON.stringify({"token":jwt_token, "user":current_user}))

func _load_auth():
	if not FileAccess.file_exists("user://deadzone_auth.json"): return
	var fa = FileAccess.open("user://deadzone_auth.json", FileAccess.READ)
	var j = JSON.parse_string(fa.get_as_text())
	if j:
		jwt_token = j.get("token","")
		current_user = j.get("user",{})
		current_user_id = int(current_user.get("id", _decode(j.get("token","")).get("id",0)))
		if jwt_token != "" and _is_valid(jwt_token):
			sync_status="synced"; auth_changed.emit(true, current_user.get("username",""))
		else:
			sync_status="offline"

func _decode(t:String) -> Dictionary:
	var p=t.split("."); if p.size()<2: return {}
	var s=p[1]; while s.length()%4!=0: s+="="; s=s.replace("-","+").replace("_","/")
	var d=Marshalls.base64_to_utf8(s); var j=JSON.parse_string(d); return j if j is Dictionary else {}

func _is_valid(t:String) -> bool:
	var p=_decode(t); if p.is_empty() or not p.has("exp"): return false; return int(p["exp"]) > int(Time.get_unix_time_from_system())

func login(email:String, password:String, cb:Callable):
	var h=HTTPRequest.new(); add_child(h)
	h.request_completed.connect(func(_r,c,_h,b):
		if c==200:
			var j=JSON.parse_string(b.get_string_from_utf8()); jwt_token=j.get("token",""); current_user=j.get("user",{}); current_user_id=int(current_user.get("id",0)); _save_auth(); auth_changed.emit(true, current_user.get("username","")); sync_status="synced"; cb.call(true,j)
		else: cb.call(false,null)
		h.queue_free(), CONNECT_ONE_SHOT)
	h.request(backend_url+"/api/auth/login", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"email":email,"password":password}))

func register_user(username:String,email:String,password:String,continent_id:int,cb:Callable):
	var h=HTTPRequest.new(); add_child(h)
	h.request_completed.connect(func(_r,c,_h,b):
		if c==201:
			var j=JSON.parse_string(b.get_string_from_utf8()); jwt_token=j.get("token",""); current_user=j.get("user",{}); current_user_id=int(current_user.get("id",0)); _save_auth(); auth_changed.emit(true, current_user.get("username","")); sync_status="synced"; cb.call(true,j)
		else: cb.call(false,null)
		h.queue_free(), CONNECT_ONE_SHOT)
	h.request(backend_url+"/api/auth/register", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"username":username,"email":email,"password":password,"continent_id":continent_id}))

func logout():
	jwt_token=""; current_user={}; current_user_id=0; sync_status="offline"; auth_changed.emit(false,"")
	if FileAccess.file_exists("user://deadzone_auth.json"): DirAccess.remove_absolute("user://deadzone_auth.json")

func sync_to_backend(cb:Callable=Callable()):
	if jwt_token=="" or current_user_id==0:
		if cb.is_valid(): cb.call(false, {"message":"Not logged in"}); return
	sync_status="syncing"
	var h=HTTPRequest.new(); add_child(h)
	h.request_completed.connect(func(_r,c,_h,b):
		var ok=c==200; sync_status="synced" if ok else "failed"; if cb.is_valid(): cb.call(ok, JSON.parse_string(b.get_string_from_utf8())); h.queue_free(), CONNECT_ONE_SHOT)
	h.request(backend_url+"/api/resources/"+str(current_user_id), ["Content-Type: application/json","Authorization: Bearer "+jwt_token], HTTPClient.METHOD_PUT, JSON.stringify({"food":food,"metal":metal,"ammo":ammo,"hard_currency":hard_currency}))
