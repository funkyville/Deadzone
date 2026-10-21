# Tutorial.gd — Full Last Z Part 1 opening, step-by-step (ONE PROJECT)
# Godot 4.x — Autoload as Tutorial (after DeadzoneManager)
# Persists: user://deadzone_save.json -> tutorial_step

extends Node

signal step_changed(step:int)
signal tutorial_finished

var step: int = 0:
	set(v): step=v; step_changed.emit(step); DeadzoneManager.save_game()

var steps: Array[Dictionary] = [
	{"id":"welcome", "text":"Welcome to Deadzone! Tap HQ to defend humanity.", "action":"tap_hq_btn"},
	{"id":"place_hq", "text":"Place Headquarters — your shelter heart (2×2). Tap green ghost on base grid.", "action":"place", "type":"hq"},
	{"id":"place_farm", "text":"Food is life. Place Resource Farm (1×1) next to HQ.", "action":"place", "type":"farm"},
	{"id":"inspect_farm", "text":"Tap your Farm → Inspector shows Lv.1. Tap Upgrade!", "action":"inspect"},
	{"id":"wait_upgrade", "text":"Upgrading Farm to Lv.2 — 30s (persists even if you close!). Wait for Ready!", "action":"wait"},
	{"id":"go_map", "text":"Horde surrounds you. Open Map to see Fog.", "action":"go_map"},
	{"id":"attack_tile", "text":"Tap highlighted ⚔ Lv.1 tile → Attack to clear Fog.", "action":"attack"},
	{"id":"win_runner", "text":"Runner: Dodge, shoot barrels! Auto-win in tutorial after 10s.", "action":"run"},
	{"id":"clear_map", "text":"Fog cleared! Tile rewards claimed. Expand HQ to reveal more!", "action":"expand"},
	{"id":"done", "text":"Tutorial complete! You now run Deadzone loop: Base → Map → Runner → Base.", "action":"done"},
]

var completed: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Load persisted step
	if DeadzoneManager and DeadzoneManager.has_method("save_game"):
		# DeadzoneManager holds save, but we store our step there too
		var save = _load_tutorial_state()
		if save.has("tutorial_step"):
			step = int(save["tutorial_step"])
			completed = bool(save.get("tutorial_done", false))

func _load_tutorial_state() -> Dictionary:
	if not FileAccess.file_exists(DeadzoneManager.SAVE_PATH if DeadzoneManager else "user://deadzone_save.json"):
		return {}
	var f=FileAccess.open(DeadzoneManager.SAVE_PATH, FileAccess.READ)
	var j=JSON.parse_string(f.get_as_text())
	return j if j is Dictionary else {}

func start_tutorial():
	step = 0
	completed = false
	_show_current()

func is_active() -> bool:
	return not completed and step < steps.size()

func _show_current():
	if step >= steps.size():
		_finish()
		return
	var s = steps[step]
	print("[Tutorial] Step %d: %s" % [step, s["text"]])
	# Emit to UI (Base/Map/Runner will listen and show arrow)
	# For HUD, connect to step_changed and display overlay
	if has_node("/root/Main"):
		var main = get_node("/root/Main")
		if main.has_method("show_tutorial_hint"):
			main.show_tutorial_hint(s["text"], s.get("action",""))
	# Auto actions for demo
	if s["action"] == "wait":
		# Fast-forward for tutorial: Farm upgrade is 30s but we wait in real time; if player closes, offline logic handles
		pass

func advance():
	step += 1
	if step >= steps.size():
		_finish()
	else:
		_show_current()
		DeadzoneManager.save_game() # also saves tutorial_step via include

func _finish():
	completed = true
	step = steps.size()
	tutorial_finished.emit()
	print("[Tutorial] Complete!")
	DeadzoneManager.save_game()

# Called by game events:
func on_building_placed(type:String):
	if is_active() and steps[step]["action"] == "place" and steps[step].get("type","") == type:
		advance()

func on_inspect():
	if is_active() and steps[step]["id"] == "inspect_farm":
		advance()

func on_upgrade_started():
	if is_active() and steps[step]["id"] == "wait_upgrade":
		advance()

func on_upgrade_finished():
	if is_active() and steps[step]["id"] == "wait_upgrade":
		# This is called from Building._complete_upgrade via signal
		advance()

func on_map_opened():
	if is_active() and steps[step]["id"] == "go_map":
		advance()

func on_tile_selected():
	if is_active() and steps[step]["id"] == "attack_tile":
		advance()

func on_runner_started():
	if is_active() and steps[step]["id"] == "win_runner":
		advance()

func on_runner_won():
	if is_active() and steps[step]["id"] == "win_runner":
		advance()
	elif is_active() and steps[step]["id"] == "clear_map":
		# Actually win_runner step advances to clear_map
		advance()

func on_hq_expanded():
	if is_active() and steps[step]["id"] == "clear_map":
		advance()
		# Next is done
		if is_active():
			advance()
