# SaveManager.gd — Autoload that persists everything including upgrade timers
# Godot 4.x — Project Settings → Autoload → SaveManager.gd

extends Node

const SAVE_PATH := "user://deadzone_base.json"

var last_save_unix: int = 0

func save_game():
	var data = {
		"last_save_unix": int(Time.get_unix_time_from_system()),
		"resources": {"food": ResourceManager.food, "metal": ResourceManager.metal, "hard_currency": ResourceManager.hard_currency},
		"buildings": []
	}
	var grid = get_tree().get_first_node_in_group("grid") as BaseGrid
	if grid:
		for b in grid.get_all_buildings():
			data["buildings"].append(b.to_save_dict())
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		last_save_unix = data["last_save_unix"]
		print("[SaveManager] Saved ", data["buildings"].size(), " buildings to ", SAVE_PATH)

func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveManager] No save found, starting fresh")
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var text = file.get_as_text()
	var json = JSON.parse_string(text)
	if not json:
		print("[SaveManager] Corrupt save")
		return
	print("[SaveManager] Loading save from ", json.get("last_save_unix",0))
	# Resources
	var res = json.get("resources", {})
	ResourceManager.food = int(res.get("food", 200))
	ResourceManager.metal = int(res.get("metal", 150))
	ResourceManager.hard_currency = int(res.get("hard_currency", 10))
	ResourceManager.Accum.food_accum = 0.0
	ResourceManager.Accum.metal_accum = 0.0
	# Offline time
	var saved_time = int(json.get("last_save_unix", int(Time.get_unix_time_from_system())))
	var now = int(Time.get_unix_time_from_system())
	var offline_sec = now - saved_time
	print("[SaveManager] Offline for ", offline_sec, "s")
	# Buildings
	var grid = get_tree().get_first_node_in_group("grid") as BaseGrid
	if not grid:
		print("[SaveManager] No grid yet, deferring")
		return
	for bd in json.get("buildings", []):
		var b = Building.from_save_dict(bd)
		grid.add_existing_building(b)
		# Check if upgrade should have finished offline
		b.check_offline_completion(now)
	last_save_unix = saved_time
	# Apply offline resource generation after buildings exist
	if offline_sec > 0:
		ResourceManager.apply_offline_progress(float(offline_sec))
		# Also complete any upgrades that were pending and would have finished
		# (check_offline_completion already handled per-building)
		save_game() # re-save with updated levels

func reset_save():
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	print("[SaveManager] Save reset")
